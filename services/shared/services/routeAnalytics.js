const fs = require('fs');
const path = require('path');

class RouteAnalytics {
  constructor(serviceName) {
    this.serviceName = serviceName;
    this.logsDir = path.join(__dirname, '../../logs/analytics');
    
    // Ensure logs directory exists
    this.ensureLogsDirectory();
  }

  ensureLogsDirectory() {
    try {
      if (!fs.existsSync(this.logsDir)) {
        fs.mkdirSync(this.logsDir, { recursive: true });
      }
    } catch (error) {
      console.error('Failed to create analytics logs directory:', error);
    }
  }

  getLogFileName() {
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    return path.join(this.logsDir, `routes-${this.serviceName}-${today}.log`);
  }

  logRequest(route, method, statusCode, responseTime, userAgent = '', clientIp = '') {
    const logEntry = {
      service: this.serviceName,
      route: route,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      userAgent: userAgent,
      clientIp: clientIp,
      timestamp: new Date().toISOString()
    };

    const logLine = JSON.stringify(logEntry) + '\n';
    const logFile = this.getLogFileName();

    try {
      fs.appendFileSync(logFile, logLine);
    } catch (error) {
      console.error('Failed to write route analytics log:', error);
      // Don't throw - logging failure shouldn't break the request
    }
  }

  // Express middleware factory
  createMiddleware() {
    return (req, res, next) => {
      const startTime = Date.now();
      
      // Capture the original end function
      const originalEnd = res.end;
      
      // Override res.end to log when response completes
      res.end = (...args) => {
        const responseTime = Date.now() - startTime;
        
        // Log the request
        this.logRequest(
          req.path,
          req.method,
          res.statusCode,
          responseTime,
          req.get('User-Agent') || '',
          req.ip || req.connection.remoteAddress || ''
        );
        
        // Call the original end function
        originalEnd.apply(res, args);
      };
      
      next();
    };
  }

  // Utility method to read and parse logs for analysis
  readLogs(days = 1) {
    const logs = [];
    
    for (let i = 0; i < days; i++) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const dateStr = date.toISOString().split('T')[0];
      const logFile = path.join(this.logsDir, `routes-${this.serviceName}-${dateStr}.log`);
      
      try {
        if (fs.existsSync(logFile)) {
          const content = fs.readFileSync(logFile, 'utf8');
          const lines = content.trim().split('\n').filter(line => line);
          
          for (const line of lines) {
            try {
              logs.push(JSON.parse(line));
            } catch (parseError) {
              console.warn('Failed to parse log line:', line);
            }
          }
        }
      } catch (error) {
        console.error(`Failed to read log file ${logFile}:`, error);
      }
    }
    
    return logs;
  }

  // Simple analytics methods
  getRouteStats(days = 1) {
    const logs = this.readLogs(days);
    const stats = {};
    
    logs.forEach(log => {
      const key = `${log.method} ${log.route}`;
      if (!stats[key]) {
        stats[key] = {
          requests: 0,
          totalResponseTime: 0,
          errors: 0,
          statusCodes: {}
        };
      }
      
      stats[key].requests++;
      stats[key].totalResponseTime += log.responseTime;
      
      if (log.statusCode >= 400) {
        stats[key].errors++;
      }
      
      stats[key].statusCodes[log.statusCode] = (stats[key].statusCodes[log.statusCode] || 0) + 1;
    });
    
    // Calculate averages
    Object.keys(stats).forEach(key => {
      stats[key].avgResponseTime = Math.round(stats[key].totalResponseTime / stats[key].requests);
      stats[key].errorRate = ((stats[key].errors / stats[key].requests) * 100).toFixed(2);
      delete stats[key].totalResponseTime; // Remove internal calculation field
    });
    
    return stats;
  }

  getTopRoutes(days = 1, limit = 10) {
    const stats = this.getRouteStats(days);
    return Object.entries(stats)
      .sort(([,a], [,b]) => b.requests - a.requests)
      .slice(0, limit)
      .map(([route, data]) => ({ route, ...data }));
  }
}

module.exports = RouteAnalytics;