# Use a CentOS base image
FROM registry.access.redhat.com/ubi8/ubi:8.6

# Update the package repository and install packages
# (Replace with your desired packages)
RUN yum update -y &&\
    yum clean all && \
    rm -rf /var/cache/yum

# Optional: Add a command to keep the container running
CMD ["tail", "-f", "/dev/null"]
