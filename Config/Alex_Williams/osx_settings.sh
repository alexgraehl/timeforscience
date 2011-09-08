#!/bin/sh

# List is mostly collected from here: https://github.com/mathiasbynens/dotfiles/blob/master/.osx
# With some modifications.

# Enable the 2D Dock
defaults write com.apple.dock no-glass -bool true

# Disable menu bar transparency
defaults write -g AppleEnableMenuBarTransparency -bool false

# Expand save panel by default
defaults write -g NSNavPanelExpandedStateForSaveMode -bool true

# Expand print panel by default
defaults write -g PMPrintingExpandedStateForPrint -bool true

##### Disable shadow in screenshots
##### defaults write com.apple.screencapture disable-shadow -bool true

# Enable highlight hover effect for the grid view of a stack (Dock)
defaults write com.apple.dock mouse-over-hilte-stack -bool true

# Disable press-and-hold for keys in favor of key repeat
defaults write -g ApplePressAndHoldEnabled -bool false

# Disable auto-correct
######### defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable window animations
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

# Disable disk image verification
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

# Automatically open a new Finder window when a volume is mounted
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true

# Avoid creating .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Disable Safari’s thumbnail cache for History and Top Sites
defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2

# Enable Safari’s debug menu
defaults write com.apple.Safari IncludeDebugMenu -bool true

# Remove useless icons from Safari’s bookmarks bar
defaults write com.apple.Safari ProxiesInBookmarksBar "()"

# Disable send and reply animations in Mail.app
defaults write com.apple.Mail DisableReplyAnimations -bool true
defaults write com.apple.Mail DisableSendAnimations -bool true

# Disable Resume for Preview.app
defaults write com.apple.Preview NSQuitAlwaysKeepsWindows -bool false

# Enable Dashboard dev mode (allows keeping widgets on the desktop)
########## defaults write com.apple.dashboard devmode -bool true

# Reset Launchpad
rm ~/Library/Application\ Support/Dock/*.db

# Show the ~/Library folder
chflags nohidden ~/Library

# Disable local Time Machine backups
######### sudo tmutil disablelocal

# Kill affected applications
for app in Safari Finder Dock Mail; do killall "$app"; done

# Fix for the ancient UTF-8 bug in QuickLook (http://mths.be/bbo)
######## echo "0x08000100:0" > ~/.CFUserTextEncoding
