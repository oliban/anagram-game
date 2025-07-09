const { Server } = require('socket.io');

let io;

function init(httpServer) {
  io = new Server(httpServer, {
    path: '/socket.io/monitoring',
    cors: {
      origin: "*", // In production, you should restrict this to the dashboard's URL
      methods: ["GET"]
    }
  });

  const monitoringNamespace = io.of('/monitoring');

  monitoringNamespace.on('connection', (socket) => {
    console.log('✅ [MONITORING] Dashboard client connected:', socket.id);

    // Send a welcome message
    socket.emit('system-message', { message: 'Connected to Anagram Game Monitoring Service' });

    socket.on('disconnect', () => {
      console.log('🛑 [MONITORING] Dashboard client disconnected:', socket.id);
    });
  });

  console.log('📈 [MONITORING] Monitoring service initialized and attached to /monitoring namespace.');

  return {
    broadcastEvent,
  };
}

function broadcastEvent(eventName, data) {
  if (io) {
    io.of('/monitoring').emit(eventName, {
        ...data,
        timestamp: new Date().toISOString(),
    });
  } else {
    console.warn('[MONITORING] Warning: Attempted to broadcast event before service was initialized.');
  }
}

module.exports = {
  init,
  broadcastEvent
}; 