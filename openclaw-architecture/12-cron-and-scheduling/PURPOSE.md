# Cron & Scheduling — Purpose

## Why This System Exists

Scheduling lets the agent **act autonomously** on a timer — sending daily summaries, checking for updates, running maintenance tasks, or executing any user-defined job on a recurring schedule.

## The Problem It Solves

1. **Autonomous operation**: Without scheduling, the agent only responds to messages. Cron jobs let it initiate actions: "Every morning at 9am, summarize my unread emails" or "Every hour, check the deployment status."

2. **Reliable execution**: Jobs persist across restarts. If the system was down when a job was due, it catches up on missed jobs at startup. Exponential backoff handles transient failures without flooding the system.

3. **Flexible scheduling**: Three schedule types cover all use cases — one-time ("at 5pm today"), recurring interval ("every 30 minutes"), and cron expressions ("0 9 * * MON-FRI" with timezone support).

4. **Failure management**: Consecutive errors trigger exponential backoff (30s → 1min → 5min → 15min → 60min) and optional failure alerts after N errors. One-shot jobs retry on transient errors; recurring jobs shift their next run time.

## What iRelay Needs from This

iRelay needs a timer-based heartbeat loop (wake every 1-60 seconds, check for due jobs), persistent job storage (JSON with atomic writes), and the backoff/retry logic. The cron expression parsing can use a Swift cron library. The key design choice is the single-timer pattern: one setTimeout for the next soonest job, not one timer per job.

## Key Insight for Replication

The scheduler is a **single-threaded timer loop** with a persistent job store. It wakes up, checks what's due, executes in parallel (up to a concurrency limit), records results, recomputes next-run times, and goes back to sleep. Simple, but the error handling and persistence make it reliable.
