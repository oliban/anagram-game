# Unified Web Component System Plan

## Overview: Shared Web Infrastructure for Two Features

### Feature 1: Game Activity Monitoring Dashboard
- **Purpose**: Real-time game activity tracking for developers/admins
- **Users**: Internal team, server administrators
- **Access**: Protected/authenticated access

### Feature 2: External Phrase Contribution System
- **Purpose**: Allow non-players to contribute phrases via shareable links
- **Users**: Friends, family, external contributors
- **Access**: Public via shareable links

## Technical Architecture

### Shared Foundation
- **Single Node.js web server** serving both features
- **Shared API endpoints** (existing phrase creation API)
- **Common UI components** (form inputs, validation, styling)
- **Unified build system** and deployment

### Directory Structure
```
web-dashboard/
├── public/
│   ├── monitoring/           # Monitoring dashboard
│   │   ├── index.html
│   │   ├── monitoring.js
│   │   └── monitoring.css
│   ├── contribute/           # External phrase contribution
│   │   ├── index.html
│   │   ├── contribute.js
│   │   └── contribute.css
│   └── shared/               # Shared components
│       ├── api-client.js
│       ├── validation.js
│       └── shared.css
├── server/
│   ├── web-routes.js         # Routes for web pages
│   └── link-generator.js     # Contribution link generation
└── package.json
```

## Feature 1: Monitoring Dashboard

### Game Events to Track:
- **Player Activity**: connections, registrations, disconnections
- **Phrase Lifecycle**: creation, consumption, completion, skips
- **Game Actions**: hint usage, scoring, language selection
- **Real-time Stats**: online players, active phrases, completion rates

### UI Components:
- **Live Activity Feed**: Real-time event stream
- **Current Game State**: Active players and phrases
- **Quick Stats**: Players online, phrases created today
- **Event Filters**: By type (player, phrase, game)

### Implementation Details:
- **WebSocket Connection**: Connect to existing `/monitoring` namespace
- **Event Categories**: Parse existing log events for game activity
- **Real-time Updates**: Live feed of player actions and game events
- **Simple Metrics**: Basic counters and current state display

## Feature 2: External Phrase Contribution

### User Flow:
1. **iOS App**: Player taps "Request External Phrase"
2. **Link Generation**: Server creates unique contribution link
3. **Sharing**: Player shares link via message/email
4. **Contribution**: External person visits link, submits phrase
5. **Delivery**: Phrase appears in player's game queue

### Technical Implementation:

#### Backend Components:
1. **Contribution Link System**:
   - Generate unique, time-limited tokens
   - Associate tokens with requesting player
   - Track link usage and expiration

2. **New API Endpoints**:
   - `POST /api/contribution/request` - Generate link for player
   - `GET /api/contribution/:token` - Validate token, show form
   - `POST /api/contribution/:token/submit` - Submit phrase

3. **Database Schema**:
   ```sql
   CREATE TABLE contribution_links (
     id UUID PRIMARY KEY,
     token VARCHAR(255) UNIQUE,
     requesting_player_id UUID,
     created_at TIMESTAMP,
     expires_at TIMESTAMP,
     used_at TIMESTAMP,
     contributor_name VARCHAR(255),
     is_active BOOLEAN DEFAULT true
   );
   ```

#### Frontend Components:
1. **Contribution Form**:
   - Phrase input with validation
   - Clue/hint input
   - Language selection
   - Contributor name (optional)
   - Real-time difficulty analysis

2. **Success/Error States**:
   - Validation feedback
   - Submission confirmation
   - Link expiration handling
   - Error messages

### Security & Validation:
- **Token-based access** (no authentication required)
- **Rate limiting** per token and IP
- **Input validation** (same as app)
- **Link expiration** (24-48 hours)
- **Profanity filtering** for external submissions

## Shared Components

### API Client Library:
- **Unified HTTP client** for both features
- **Error handling** and retry logic
- **WebSocket integration** for real-time updates
- **Validation helpers** for form inputs

### Common UI Elements:
- **Phrase input forms** with validation
- **Language selection** components
- **Difficulty indicators**
- **Loading states** and error messages
- **Responsive design** for mobile/desktop

## Implementation Strategy

### Phase 1: Foundation (Week 1)
- Set up shared web server structure
- Create basic HTML/CSS/JS framework
- Implement shared API client
- Basic monitoring dashboard

### Phase 2: Monitoring Dashboard (Week 2)
- WebSocket integration for real-time events
- Game event tracking and display
- Activity feed and stats panels
- Event filtering and search

### Phase 3: Contribution System (Week 3)
- Contribution link generation system
- Token validation and management
- External phrase submission form
- Integration with existing phrase API

### Phase 4: Polish & Integration (Week 4)
- iOS app integration for link generation
- Mobile-responsive design
- Security hardening
- Performance optimization

## Detailed Technical Specifications

### Monitoring Dashboard Endpoints:
- `GET /monitoring` - Dashboard HTML page
- `GET /monitoring/events` - Server-sent events stream
- `WebSocket /monitoring` - Real-time event updates

### Contribution System Endpoints:
- `POST /api/contribution/request` - Generate contribution link
- `GET /contribute/:token` - Contribution form page
- `POST /api/contribution/:token/submit` - Submit phrase
- `GET /api/contribution/:token/status` - Check token validity

### Database Integration:
- **Existing Tables**: players, phrases, player_phrases
- **New Table**: contribution_links
- **Foreign Keys**: contribution_links.requesting_player_id → players.id

### iOS App Integration:
- **New NetworkManager Method**: `requestContributionLink()`
- **Share Dialog**: Native iOS share sheet with generated link
- **Notification**: Alert when external phrase is received

### Security Considerations:
- **CORS Settings**: Allow contribution domain
- **Rate Limiting**: Prevent abuse of contribution endpoints
- **Input Sanitization**: XSS prevention for external submissions
- **Token Validation**: Cryptographically secure tokens
- **Expiration Handling**: Automatic cleanup of expired links

## Benefits of Unified Approach:
- **Code reuse**: Shared components and validation
- **Consistent UX**: Similar look and feel
- **Easier maintenance**: Single web infrastructure
- **Faster development**: Leverage existing API
- **Better security**: Centralized validation and rate limiting

## Next Steps:
1. **Create web-dashboard directory structure**
2. **Set up basic HTML/CSS/JS framework**
3. **Integrate monitoring service into main server**
4. **Implement contribution link generation**
5. **Build monitoring dashboard UI**
6. **Create contribution form interface**
7. **Add iOS app integration**
8. **Test and deploy**

This plan creates a solid foundation for both features while maximizing code reuse and maintaining a consistent user experience.