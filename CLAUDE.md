# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
iOS "Anagram Game" for iPhone and Apple Watch built with SwiftUI. Players drag letter tiles to form words from scrambled sentences.

## Development Workflow
- **Progress Tracking**: Update `DEVELOPMENT_PROGRESS.md` checkboxes as steps complete
- **Current Focus**: Following 8-step implementation plan from project setup through Apple Watch version
- **Time Estimates**: Each step has rough time estimates (30-120 minutes) for session planning

## Key Architecture
- **GameModel**: Core game logic with ObservableObject for state management
- **TileView**: Draggable SwiftUI components for letter tiles
- **GameView**: Main iPhone interface with tile grid and word formation zones
- **WatchGameView**: Simplified Apple Watch version
- **anagrams.txt**: Plain text file with sentences (one per line)

## Project Structure
```
Models/         - GameModel and data logic
Views/          - SwiftUI views (GameView, TileView, etc.)
Resources/      - anagrams.txt and assets
Watch/          - Apple Watch specific code
```

## Development Commands
- Build: `⌘+B` in Xcode
- Run on simulator: `⌘+R` in Xcode
- Run tests: `⌘+U` in Xcode
- Clean build: `⌘+Shift+K` in Xcode

## Current Implementation Status
Track progress in `DEVELOPMENT_PROGRESS.md` - update checkboxes as each step completes.

## Claude Interactions
- You don't build the app! I do.