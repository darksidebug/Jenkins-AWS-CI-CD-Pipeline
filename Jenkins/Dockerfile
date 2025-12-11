FROM jenkins/jenkins:lts

USER root

# Install Docker CLI and docker-compose
RUN apt-get update && apt-get install -y \
  docker.io \
  docker-compose \
  git \
  curl \
  sudo \
  && rm -rf /var/lib/apt/lists/*

# Add jenkins user to docker group
RUN usermod -aG docker jenkins

USER jenkins
