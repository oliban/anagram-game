/**
 * Authentication middleware for admin endpoints
 * Provides API key-based authentication with development-friendly defaults
 */

/**
 * Admin API Key authentication middleware
 * Validates X-API-Key header against configured admin key
 */
const requireAdminApiKey = (req, res, next) => {
  // Skip auth in development if security is relaxed
  const isDevelopment = process.env.NODE_ENV === 'development';
  const isSecurityRelaxed = process.env.SECURITY_RELAXED === 'true';
  
  if (isDevelopment && isSecurityRelaxed) {
    console.log('🔓 AUTH: Bypassing admin auth in relaxed development mode');
    return next();
  }

  const apiKey = req.headers['x-api-key'];
  const expectedKey = process.env.ADMIN_API_KEY;

  // Log authentication attempt
  if (process.env.LOG_SECURITY_EVENTS === 'true') {
    console.log('🔑 AUTH: Admin API key attempt', {
      provided: apiKey ? 'present' : 'missing',
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      endpoint: req.path
    });
  }

  if (!expectedKey) {
    console.error('❌ AUTH: ADMIN_API_KEY not configured');
    return res.status(500).json({
      error: 'Server configuration error',
      message: 'Authentication not properly configured'
    });
  }

  if (!apiKey) {
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log('🚫 AUTH: Missing API key for admin endpoint');
    }
    return res.status(401).json({
      error: 'Authentication required',
      message: 'X-API-Key header is required for admin endpoints'
    });
  }

  if (apiKey !== expectedKey) {
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log('🚫 AUTH: Invalid API key provided');
    }
    return res.status(403).json({
      error: 'Authentication failed',
      message: 'Invalid API key'
    });
  }

  // Log successful authentication
  if (process.env.LOG_SECURITY_EVENTS === 'true') {
    console.log('✅ AUTH: Admin API key validated successfully');
  }

  next();
};

/**
 * Optional API key middleware - allows requests without key but logs attempts
 * Useful for gradual rollout or monitoring
 */
const optionalAdminApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  if (process.env.LOG_SECURITY_EVENTS === 'true') {
    console.log('🔍 AUTH: Optional auth check', {
      hasKey: !!apiKey,
      endpoint: req.path,
      ip: req.ip
    });
  }

  // Always proceed, but mark the request
  req.hasValidApiKey = apiKey === process.env.ADMIN_API_KEY;
  next();
};

/**
 * Health check bypass middleware - always allows access to health endpoints
 */
const allowHealthChecks = (req, res, next) => {
  const healthEndpoints = ['/api/status', '/health', '/ping'];
  
  if (healthEndpoints.includes(req.path)) {
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log('🩺 AUTH: Allowing health check endpoint:', req.path);
    }
    return next();
  }
  
  // Not a health endpoint, continue to actual auth
  requireAdminApiKey(req, res, next);
};

module.exports = {
  requireAdminApiKey,
  optionalAdminApiKey,
  allowHealthChecks
};