# Serves the project page from an image that already runs as non-root.
FROM nginxinc/nginx-unprivileged:1.30.4-alpine@sha256:45ce1e2e699234253d1def7baa96218a5d00b498d1ba0cbb1a17b6bdf73d1351

# The entrypoint runs envsubst on this at startup, which carries Pod facts.
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html

# Sourced before the template is filled in, so RUNTIME_UID exists in time.
COPY 10-runtime-facts.envsh /docker-entrypoint.d/10-runtime-facts.envsh

# Limits envsubst to this project's variables, so nginx's own are left alone.
ENV NGINX_ENVSUBST_FILTER="^(POD_|NODE_|IMAGE_|RUNTIME_)"

# A port below 1024 needs a capability the restricted standard forbids.
EXPOSE 8080

LABEL org.opencontainers.image.title="k8-lab frontend" \
      org.opencontainers.image.source="https://github.com/sindredg/k8-lab"
