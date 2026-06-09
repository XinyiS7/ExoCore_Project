# ExoCore Nginx — minimal image, config only.
# Frontend dist/ files are bind-mounted at runtime (not baked into image).
# This means `pnpm build` on the host takes effect immediately — no rebuild needed.

FROM nginx:alpine

# Remove default config
RUN rm -f /etc/nginx/conf.d/default.conf

# Copy our config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
