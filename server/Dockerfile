# Use Node.js 18 Alpine for smaller image size
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy package files first for better Docker layer caching
COPY server/package*.json ./

# Install production dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy server application code
COPY server/ ./

# Copy shared directories needed by the server
COPY shared/ ./shared/
COPY web-dashboard/ ./web-dashboard/

# Create necessary directories
RUN mkdir -p logs && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Expose port (Fargate will map this dynamically)
EXPOSE 3000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/status', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Start the application
CMD ["npm", "start"]