Use these files to debug vitals' generation and serving of logs.

The .R file implements a similar example eval with vitals that the .py file
implements with Inspect. Run both to generate logs, the latter using 
inst/debug/inspeect as the log directory. 

Then, try to view both. If, with `inspect view --log-dir`, you can view the
Inspect log but not the vitals one, then there's an issue with the log generation.

If there are issues viewing either log directory with `vitals::vitals_view()`, 
you know there's an issue with vitals' log viewer code.
