#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup SSH key with automated configuration and backup

OPTIONS:
    -n, --name <name>       Name for the SSH key (e.g., github-personal)
    -e, --email <email>     Email address for the SSH key
    -t, --title <title>     Title for GitHub key (optional, defaults to hostname)
    -h, --help             Show this help message

EXAMPLE:
    $0 -n github-personal -e user@example.com
    $0 --name work --email work@company.com --title "Work Laptop"

EOF
    exit 0
}

# Parse command line arguments
KEY_NAME=""
EMAIL=""
GH_TITLE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            KEY_NAME="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -t|--title)
            GH_TITLE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$KEY_NAME" ]]; then
    print_error "Key name is required"
    usage
fi

if [[ -z "$EMAIL" ]]; then
    print_error "Email is required"
    usage
fi

# Set default GitHub title if not provided
if [[ -z "$GH_TITLE" ]]; then
    GH_TITLE="$(hostname)"
fi

# Define key paths
SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="$SSH_DIR/id_$KEY_NAME"
PUBLIC_KEY="$PRIVATE_KEY.pub"
SSH_CONFIG="$SSH_DIR/config"

print_info "SSH Key Setup"
echo "  Name:  $KEY_NAME"
echo "  Email: $EMAIL"
echo "  Path:  $PRIVATE_KEY"
echo ""

# Check if key already exists
if [[ -f "$PRIVATE_KEY" ]]; then
    print_warning "SSH key '$KEY_NAME' already exists!"
    echo ""
    print_info "Private key: $PRIVATE_KEY"
    print_info "Public key:  $PUBLIC_KEY"
    echo ""

    if [[ -f "$PUBLIC_KEY" ]]; then
        print_info "Public key content:"
        cat "$PUBLIC_KEY"
    fi

    echo ""
    print_error "Key already exists. Please use a different name or delete the existing key."
    exit 1
fi

# Ensure .ssh directory exists
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Step 1: Generate SSH key
print_info "Step 1: Generating SSH key..."
ssh-keygen -t ed25519 -C "$EMAIL" -f "$PRIVATE_KEY" -N ""
print_success "SSH key generated"

# Step 2: Add entry to SSH config
print_info "Step 2: Adding entry to SSH config..."

# Create config file if it doesn't exist
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Add Host entry
cat >> "$SSH_CONFIG" << EOF

# $KEY_NAME - Added $(date +"%Y-%m-%d %H:%M:%S")
Host $KEY_NAME
    HostName github.com
    User git
    IdentityFile $PRIVATE_KEY
    UseKeychain yes
    AddKeysToAgent yes
EOF

print_success "SSH config entry added"

# Step 3: Add key to ssh-agent and store passphrase in keychain
print_info "Step 3: Adding key to ssh-agent..."

# Start ssh-agent if not running
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi

# Add key to agent (on macOS, this also stores it in keychain)
ssh-add --apple-use-keychain "$PRIVATE_KEY" 2>/dev/null || ssh-add "$PRIVATE_KEY"
print_success "Key added to ssh-agent and keychain"

# Step 4: Save private key to Bitwarden
print_info "Step 4: Saving private key to Bitwarden..."

# Check if rbw CLI is available
if ! command -v rbw &> /dev/null; then
    print_error "Bitwarden CLI (rbw) is not installed"
    print_warning "Skipping Bitwarden backup"
else
    # Check if unlocked (rbw unlocked returns 0 if unlocked, 1 if locked)
    if ! rbw unlocked &> /dev/null; then
        print_warning "Bitwarden is not unlocked. Please run: rbw unlock"
        print_warning "Skipping Bitwarden backup"
    else
        # Read private key content
        PRIVATE_KEY_CONTENT=$(cat "$PRIVATE_KEY")

        # Create the note content
        NOTE_CONTENT="SSH Private Key
Email: $EMAIL
Generated: $(date)

$PRIVATE_KEY_CONTENT"

        # Create secure note item in Bitwarden using rbw
        echo "$NOTE_CONTENT" | rbw add "SSH Key - $KEY_NAME" --folder "SSH Keys" 2>/dev/null || \
        echo "$NOTE_CONTENT" | rbw add "SSH Key - $KEY_NAME" 2>/dev/null

        print_success "Private key saved to Bitwarden"
    fi
fi

# Step 5: Add public key to GitHub
print_info "Step 5: Adding public key to GitHub..."

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed"
    print_warning "Skipping GitHub upload"
else
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub. Please run: gh auth login"
        print_warning "Skipping GitHub upload"
    else
        # Try to add SSH key to GitHub
        if ! gh ssh-key add "$PUBLIC_KEY" --title "$GH_TITLE - $KEY_NAME" 2>&1 | tee /dev/stderr | grep -q "admin:public_key"; then
            if gh ssh-key list &> /dev/null; then
                # Key was added successfully
                print_success "Public key added to GitHub"
            else
                # Some other error occurred
                print_error "Failed to add SSH key to GitHub"
                print_warning "Skipping GitHub upload"
            fi
        else
            # Need to refresh with admin:public_key scope
            print_warning "GitHub CLI needs additional permissions"
            print_info "Requesting admin:public_key scope..."

            if gh auth refresh -h github.com -s admin:public_key; then
                print_success "Permissions granted"

                # Try adding the key again
                if gh ssh-key add "$PUBLIC_KEY" --title "$GH_TITLE - $KEY_NAME"; then
                    print_success "Public key added to GitHub"
                else
                    print_error "Failed to add SSH key to GitHub"
                    print_warning "Skipping GitHub upload"
                fi
            else
                print_error "Failed to refresh GitHub authentication"
                print_info "You can manually add the key later with:"
                echo "  gh auth refresh -h github.com -s admin:public_key"
                echo "  gh ssh-key add \"$PUBLIC_KEY\" --title \"$GH_TITLE - $KEY_NAME\""
            fi
        fi
    fi
fi

# Summary
echo ""
print_success "SSH key setup complete!"
echo ""
print_info "Summary:"
echo "  Private key: $PRIVATE_KEY"
echo "  Public key:  $PUBLIC_KEY"
echo "  SSH config:  Host '$KEY_NAME' added"
echo ""
print_info "To use this key with Git:"
echo "  git clone git@$KEY_NAME:username/repo.git"
echo ""
print_info "Public key content:"
cat "$PUBLIC_KEY"
