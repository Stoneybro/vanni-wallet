docker system prune -f
docker volume rm  indexer_envio-indexer-storage
docker compose up --build
