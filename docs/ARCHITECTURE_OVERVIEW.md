# Architecture Overview

## System Architecture

### High-Level Overview
**Client-Server**: iOS SwiftUI + SpriteKit ↔ Docker Services ↔ Shared PostgreSQL

```
┌─────────────────────────────────────────┐
│           iOS Apps (SwiftUI)            │
│         + SpriteKit Engine              │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│      Game Server (Port 3000)            │
│  • Core API + WebSocket                 │
│  • Contribution System (Consolidated)    │
│  • Player Management                    │
│  • Phrase Operations                    │
│  • Real-time Multiplayer               │
└─────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│   Web    │ │PostgreSQL│ │ External │
│Dashboard │ │    DB    │ │Services  │
│  (3001)  │ │  (5432)  │ │(Optional)│
└──────────┘ └──────────┘ └──────────┘
```

## Microservices Architecture

### Current Service Layout
After the August 2025 consolidation:

#### Game Server (Port 3000) - Core Service
- **Core multiplayer API** with RESTful endpoints
- **WebSocket real-time communication** for live gameplay
- **Contribution system** (consolidated from separate service)
- **Player management** and authentication
- **Phrase operations** and difficulty scoring
- **Statistics and leaderboards**

#### Web Dashboard (Port 3001) - Monitoring
- **Real-time monitoring interface**
- **System health dashboard**
- **Player and phrase statistics**
- **Administrative visibility**

#### PostgreSQL Database (Port 5432) - Shared Data
- **Single source of truth** for all game data
- **Players, phrases, statistics** storage
- **Shared schema** across all services
- **Transaction support** for data consistency

### Consolidated Architecture Benefits
- **Reduced complexity**: From 4 to 3 services
- **Better performance**: Direct API calls, no service-to-service overhead
- **Simplified deployment**: Fewer containers to manage
- **Easier debugging**: Centralized game logic

## Technology Stack

### iOS Client
- **SwiftUI**: Modern declarative UI framework
- **SpriteKit**: 2D game engine for tile animations
- **URLSession**: HTTP API communication
- **Socket.IO**: Real-time WebSocket communication
- **Swift Concurrency**: async/await for networking

### Backend Services
- **Node.js**: JavaScript runtime for all services
- **Express.js**: Web application framework
- **Socket.IO**: Real-time bidirectional communication
- **PostgreSQL**: Relational database with JSON support
- **Docker**: Containerization for all services
- **docker-compose**: Service orchestration

### Development & Deployment
- **Xcode**: iOS development environment
- **Docker Desktop**: Local development containers
- **Git**: Version control with GitFlow workflow
- **GitHub Actions**: CI/CD automation
- **Cloudflare Tunnel**: Staging server public access
- **AWS ECS**: Production container orchestration

## Data Architecture

### Database Schema
```sql
-- Core tables
players (id, name, language, is_online, created_at, stats)
phrases (id, content, hint, difficulty_level, language, sender_id, target_id)
completions (phrase_id, player_id, completion_time, hints_used)
contributions (token, phrase_content, status, created_at)

-- Indexes for performance
CREATE INDEX idx_players_online ON players(is_online);
CREATE INDEX idx_phrases_target ON phrases(target_id);
CREATE INDEX idx_phrases_difficulty ON phrases(difficulty_level);
```

### Shared Algorithm Architecture
**Configuration-Based Scoring**: Both iOS and server read from `shared/difficulty-algorithm-config.json`
- **Single source of truth** eliminates code duplication
- **Client-side scoring** eliminates network calls during typing
- **Consistent difficulty** across all game components

### Data Flow Patterns
1. **User Action** (iOS) → API Call → Database Update
2. **Database Change** → WebSocket Event → Real-time UI Update
3. **Phrase Generation** → AI Processing → Database Import → Game Integration

## Network Architecture

### Communication Patterns

#### HTTP API (Request-Response)
- **Player registration and management**
- **Phrase creation and completion**
- **Statistics and leaderboard queries**
- **Configuration and system status**

#### WebSocket (Real-time)
- **New phrase notifications**
- **Player join/leave events**
- **Completion celebrations**
- **Live player counts**

#### Direct Database (Import/Export)
- **Phrase generation imports**
- **Backup and restore operations**
- **Administrative data operations**

### Security Architecture
- **CORS protection** with environment-specific policies
- **Rate limiting** to prevent abuse
- **Input validation** with XSS/injection protection
- **No admin HTTP APIs** - direct database access only

## Performance Standards

### iOS Performance Targets
- **Launch time**: <3 seconds from tap to gameplay
- **Memory usage**: <100MB baseline, <200MB peak
- **Frame rate**: 60fps for animations and interactions
- **API timeout**: 10 seconds maximum for any request
- **Offline capability**: Graceful degradation without network

### Backend Performance Targets
- **API response time**: <200ms average for all endpoints
- **Database queries**: <50ms for standard operations
- **WebSocket latency**: <100ms for real-time events
- **Uptime**: 99.9% availability target
- **Memory per service**: <512MB per Docker container

### Monitoring Standards
- **iOS**: Use Instruments for performance profiling
- **Backend**: Monitor with `curl -w` for API timing
- **Database**: Query performance analysis with PostgreSQL stats
- **Real-time**: WebSocket connection monitoring
- **System**: Docker container resource monitoring

## Scalability Design

### Horizontal Scaling Considerations
- **Stateless services** enable multiple instances
- **Database connection pooling** handles concurrent load
- **WebSocket load balancing** with sticky sessions
- **CDN support** for static assets (future)

### Vertical Scaling Patterns
- **PostgreSQL** can scale with better hardware
- **Node.js services** benefit from more CPU cores
- **Memory optimization** through efficient data structures
- **Container resource limits** prevent resource starvation

### Performance Bottlenecks
- **Database queries** - most likely bottleneck
- **WebSocket connections** - memory intensive
- **AI phrase generation** - CPU intensive
- **iOS rendering** - GPU/memory bound

## Development Architecture

### MVVM Pattern (iOS)
```swift
// Model Layer
@Observable GameModel {
    // Game state and business logic
}

// View Layer
struct GameView: View {
    // SwiftUI declarative UI
}

// ViewModel Layer
NetworkManager {
    // API communication and state updates
}
```

### Service Layer Pattern (Backend)
```javascript
// Controller Layer
app.post('/api/phrases', phraseController.create);

// Service Layer
phraseService.createPhrase(data);

// Data Access Layer
phraseRepository.save(phrase);
```

### Shared Components
- **Difficulty algorithm** used by both iOS and server
- **Validation rules** consistent across all entry points
- **Data models** shared schema definitions
- **Configuration files** environment-specific settings

## Deployment Architecture

### Environment Separation
- **Local Development**: Docker Compose with local networking
- **Pi Staging**: Cloudflare Tunnel with dynamic URLs
- **AWS Production**: ECS with load balancer and auto-scaling

### Container Architecture
```yaml
# docker-compose.services.yml
services:
  game-server:
    build: ./services/game-server
    ports: ["3000:3000"]
    depends_on: [postgres]
  
  web-dashboard:
    build: ./services/web-dashboard
    ports: ["3001:3001"]
    depends_on: [game-server]
  
  postgres:
    image: postgres:13
    ports: ["5432:5432"]
    volumes: [db-data:/var/lib/postgresql/data]
```

### Build and Deploy Pipeline
1. **Feature Development**: Local Docker environment
2. **Integration Testing**: Automated test suite execution
3. **Staging Deployment**: Pi server with Cloudflare Tunnel
4. **Production Release**: AWS ECS with blue-green deployment

## Security Architecture

### Defense in Depth
- **Input Validation**: All API endpoints validate and sanitize
- **Rate Limiting**: Prevent abuse and DoS attacks  
- **CORS Protection**: Restrict cross-origin requests
- **Database Security**: Parameterized queries prevent injection
- **Container Isolation**: Services run in separate containers

### Authentication & Authorization
- **Player identification**: UUID-based player IDs
- **Session management**: Stateless JWT tokens (future)
- **API key authentication**: Admin operations (future)
- **Device binding**: iOS device association for auto-login

### Security Monitoring
- **Event logging**: All security events logged with emojis
- **Rate limit tracking**: Monitor for abuse patterns
- **Input validation logs**: Track malicious input attempts
- **Real-time alerting**: Critical security events (future)

## Integration Architecture

### Third-Party Services
- **Cloudflare Tunnel**: Staging server public access
- **AWS Services**: Production hosting and scaling
- **Apple Services**: iOS distribution and device management
- **GitHub**: Source control and CI/CD automation

### API Integrations
- **RESTful APIs**: Standard HTTP/JSON communication
- **WebSocket**: Real-time bidirectional communication
- **Database APIs**: Direct PostgreSQL access for imports
- **System APIs**: Docker and container management

### Future Integration Points
- **Push notifications**: iOS native notifications
- **Analytics services**: Player behavior tracking
- **Content delivery**: Static asset optimization
- **Social features**: Player connections and sharing