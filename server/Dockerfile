# Use Node.js 18 Alpine for smaller image size
FROM node:18-alpine

# Set working directory to root level to match project structure
WORKDIR /project

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy package files first for better Docker layer caching
COPY server/package*.json ./server/

# Install production dependencies
WORKDIR /project/server
RUN npm ci --only=production && npm cache clean --force

# Copy all project structure - force rebuild for correct models
WORKDIR /project
COPY server/ ./server/
COPY services/ ./services/

# Copy shared directories needed by the server
COPY shared/ ./shared/

# Note: Don't overwrite server/models/ - it contains the correct updated models

# Set final working directory to server
WORKDIR /project/server

# Create necessary directories
RUN mkdir -p logs && \
    chown -R nodejs:nodejs /project

# Switch to non-root user
USER nodejs

# Expose port (Fargate will map this dynamically)
EXPOSE 3000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/status', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Start the application
CMD ["npm", "start"]