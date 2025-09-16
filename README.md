# Slurm Lightweight Reporting Tools

These tools can be run from the command line as any user and will query the Slurm job completion logs.

## Requirements

* Slurm logs job completion data in plain text

### slurm.conf

```
JobCompType=jobcomp/filetxt
JobCompLoc=/var/log/slurm_jobcomp.log
```
- `/var/log/slurm_jobcomp.log` is the *default* location if `JobCompLoc` is not specified in `slurm.conf`

---
## top_users_jobs.sh
## top_users_runtime.sh
Reports the top N users from Slurm logfile over X days for number of jobs, total runtime (depending).

Usage:
- users=N (default is top 5)
- days=X (default is ALL TIME)
- save=FILENAME (default is NO FILE, OUTPUT TO SCREEN)

`./top_users_job.sh users=10 days=30`

---

## slurm_user_report.sh
Generates report on specified Slurm user's jobs for X days.

Usage:
- USER_ID (Slurm User_ID)
- days=X (default is ALL TIME)

`./slurm_user_report.sh jdoe days=50`

---
Copilot helped with the syntax whenever I needed help!
