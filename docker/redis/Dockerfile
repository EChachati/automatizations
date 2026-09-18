# Dockerfile para Redis
FROM redis:7-alpine

# Crear directorio para datos persistentes
RUN mkdir -p /data

# Exponer puerto 6379
EXPOSE 6379

# Comando por defecto
CMD ["redis-server", "--appendonly", "yes"]
