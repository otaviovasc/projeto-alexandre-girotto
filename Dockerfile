# Use the official Ruby image
FROM ruby:3.2.2

# Install dependencies
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs yarn

# Set up working directory
WORKDIR /app

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the rest of the application code
COPY . .

# Precompile assets (optional, depending on your app setup)
RUN bundle exec rake assets:precompile

# Expose the Rails server port
EXPOSE 3000

# Start the Rails server
CMD ["rails", "server", "-b", "0.0.0.0"]
