# __#TEMPLATE#:DOMAIN__

Website created with [webserver-printer](https://github.com/shipurjan/webserver-printer) v__#TEMPLATE#:VERSION__.

## Development

```bash
cd frontend
npm install
npm run dev
```

## Deployment

Push to master branch - GitHub Actions will deploy automatically.

Or manually:

```bash
cd docker
docker compose build
docker compose down frontend caddy
docker volume rm $(docker volume ls -q | grep frontend_dist) || true
docker compose up -d
```
