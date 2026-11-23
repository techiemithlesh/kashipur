FROM node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

ARG VITE_REACT_APP_BACKEND_API
ARG VITE_REACT_APP_ULB_ID
ARG VITE_MAP_TILE_URL
ARG VITE_MAP_ATTRIBUTION
ARG VITE_MAP_STREET_LABELS_URL
ARG VITE_MAP_PLACE_LABELS_URL
ARG VITE_ROUTING_URL
ARG VITE_REVERB_APP_KEY
ARG VITE_REVERB_HOST
ARG VITE_REVERB_PORT
ARG VITE_REVERB_SCHEME

RUN test -n "$VITE_REACT_APP_BACKEND_API" \
    && case "$VITE_REACT_APP_BACKEND_API" in \
        */|*/api|*/api/) \
            echo >&2 "Use a backend base URL without a trailing slash or /api suffix"; \
            exit 1 ;; \
    esac \
    && npm run build

FROM nginx:alpine@sha256:892bb2152464f0c5d8972593a5f5afaf8054552580b699d95f8ff4af08c2d33d AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
