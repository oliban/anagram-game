# Game Server Dockerfile
FROM node:18-alpine

WORKDIR /app

# Install curl for health checks and create non-root user for security
RUN apk add --no-cache curl && \
    addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy package files first for better Docker layer caching
COPY game-server/package*.json ./

# Install production dependencies
RUN npm install --only=production && npm cache clean --force

# Copy application code
COPY --chown=nodejs:nodejs game-server/ ./

# Copy shared modules from services level
COPY --chown=nodejs:nodejs shared/ ./shared/

# Create necessary directories
RUN mkdir -p logs && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/status', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Start the application
CMD ["npm", "start"]