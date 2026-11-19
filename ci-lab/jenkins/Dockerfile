FROM jenkins/jenkins:2.479.1-lts-jdk17
USER root
# Docker CLI (talks to the host engine through the mounted socket), Python, ShellCheck, Ansible
RUN apt-get update \
 && apt-get install -y --no-install-recommends docker.io python3 python3-venv python3-pip shellcheck ansible \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -f docker && usermod -aG docker jenkins
USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
