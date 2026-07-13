#!/usr/bin/env bash

# Exit on any error
set -e

# Ensure the script is run from the project root
cd "$(dirname "$0")/.."

# Load local shell variables only when the file exists.
[ -f ~/.bash_profile ] && source ~/.bash_profile

# Install dependencies
bundle install --deployment --without development test

# Run database migrations
bundle exec rails db:migrate

# Precompile assets
bundle exec rails assets:precompile

# Clean up old assets
bundle exec rails assets:clean

# Restart the server (if using a process manager like puma, passenger, etc.)
# Uncomment and modify the following line based on your setup
# bundle exec passenger-config restart-app $(pwd)
# or
# systemctl restart puma

echo "Build completed successfully!"
