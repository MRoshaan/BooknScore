# 🏏 BooknScore (formerly Wicket.pk)

**BooknScore** is a professional-grade, offline-first cricket scoring application designed for both indoor turfs and outdoor tape-ball matches. It allows users to track matches ball-by-ball, manage tournaments, and sync live scorecards to the cloud for the community to follow.

## ✨ Key Features

* **Offline-First Scoring Engine:** Built with a local SQLite database to ensure the app never crashes or loses data if the internet drops at the ground.
* **Cloud Syncing:** Seamlessly pushes completed overs and match summaries to a Supabase backend when a connection is restored.
* **Live Community Scorecards:** A global feed where users can search, filter, and view ongoing and recent matches sorted from newest to oldest.
* **Dynamic Theming:** Includes a custom theme manager that toggles between a premium Dark Mode (for indoor viewing) and a high-contrast Light Mode (for direct sunlight visibility).
* **Comprehensive Stats:** Tracks player roles, team histories, match summaries, and tournament progression.

## 🛠️ Tech Stack

* **Frontend:** Flutter & Dart
* **Local Database:** SQLite (via `sqflite`)
* **Backend as a Service (BaaS):** Supabase (PostgreSQL)
* **State Management:** Provider
* **Environment Security:** `flutter_dotenv`

## 🏗️ Architecture

BooknScore utilizes a highly resilient **2-Tier Architecture**. The app interacts directly with the local SQLite database for instantaneous UI updates and offline reliability. A background `SyncService` listens for connectivity and securely syncs the local state with the Supabase PostgreSQL database using Row Level Security (RLS) policies.

## 🚀 Getting Started

To run this project locally:

1. Clone the repository:
   ```bash
   git clone [https://github.com/MRoshaan/BooknScore.git](https://github.com/YOUR_USERNAME/BooknScore.git)
