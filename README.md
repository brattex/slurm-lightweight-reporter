# Slurm Lightweight Reporting Tools
## top_users_jobs.sh
Reports the top N users from Slurm logfile over X days.

Usage:
- users=N (default is top 5)
- days=X (default is ALL TIME)
- save=FILENAME (default is NO FILE, OUTPUT TO SCREEN)

`./top_users_job.sh users=10 days=30`

## slurm_user_report.sh
Generates report on specified Slurm user's jobs for X days.

Usage:
- user=USER_ID (Slurm User_ID)
- days=X (default is ALL TIME)

`./slurm_user_report.sh user=jdoe days=50`

---
Copilot helped with the syntax whenever I needed help!
