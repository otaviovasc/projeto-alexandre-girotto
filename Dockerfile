# Use the official Ruby 3.2.2 image as a base
FROM ruby:3.2.2

# Install dependencies
RUN apt-get update -qq && apt-get install -y nodejs postgresql-client

# Set environment variable for gems
ENV BUNDLE_PATH /gems

# Set working directory inside the container
WORKDIR /myapp

# Copy the Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install

# Copy the main application
COPY . .

# Expose port 3000 to the Docker host
EXPOSE 3000

# Start the development server with Tailwind
CMD ["./bin/dev"]
