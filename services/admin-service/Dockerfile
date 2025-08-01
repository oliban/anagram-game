# Use Node.js LTS
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY admin-service/package*.json ./

# Install dependencies
RUN npm install --only=production

# Copy shared dependencies
COPY shared/ ./shared/

# Copy admin service source
COPY admin-service/ ./

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S admin -u 1001
USER admin

# Expose port
EXPOSE 3003

# Start the service
CMD ["node", "server.js"]