# Dockerfile para MongoDB con limitaciones de recursos
FROM mongo:7.0

# Configurar variables de entorno para optimizar el uso de memoria
ENV MONGO_INITDB_ROOT_USERNAME=admin
ENV MONGO_INITDB_ROOT_PASSWORD=password123
ENV MONGO_INITDB_DATABASE=testdb

# Crear directorio para datos persistentes
RUN mkdir -p /data/db

# Configurar MongoDB para usar menos memoria
RUN echo "storage:\n  wiredTiger:\n    engineConfig:\n      cacheSizeGB: 0.1" > /etc/mongod.conf

# Exponer puerto por defecto de MongoDB
EXPOSE 27017

# Comando por defecto
CMD ["mongod", "--bind_ip_all", "--port", "27017"]
