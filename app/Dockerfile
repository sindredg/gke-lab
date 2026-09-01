# Serves the project page from an NGINX image that already runs as a non-root user.
FROM nginxinc/nginx-unprivileged:1.30.4-alpine@sha256:45ce1e2e699234253d1def7baa96218a5d00b498d1ba0cbb1a17b6bdf73d1351

# Replaces the packaged server block so the listening port and probe path are declared here.
COPY default.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

# Ports below 1024 need a capability the restricted Pod Security standard forbids.
EXPOSE 8080

LABEL org.opencontainers.image.title="k8-lab frontend" \
      org.opencontainers.image.source="https://github.com/sindredg/k8-lab" \
      org.opencontainers.image.licenses="MIT"
