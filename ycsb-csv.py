import re
import sys
import csv

# The output tabular comprises the following fields
# PHASE, DB, WORKLOAD, THREADS, RECORDS, OP, METRIC, VALUE

logfile = sys.argv[1]
csvfile=sys.argv[2]

# Open the ycsb test output file
f = open(logfile)
runNum = 0

# Setup output table, enter the header record
rowcnt = 0
t = []
t.append([]) # add header row
t[rowcnt]= ['RUNID', 'DB', 'WORKLOAD', 'THREADS', 'RECORDS', 'OP', 'METRIC', 'VALUE']

# results parsing
# Good! r = re.compile(r'(\[\w+\]), (\w+\(\w+\)), (\d+.\d+)');


for l in f:

    l.rstrip()

    # look for a match of pattern bin/ycsb
    if re.search('Command line:', l):
        # capture information for the next run
        runNum = runNum + 1
        
        # get hold of the run's parameters        
        runParams = l.split(' ')
    elif re.search(r'^\[OVERALL\]'
                   '|^\[SCAN\]'
                   '|^\[INSERT\]'
                   '|^\[UPDATE\]'
                   '|^\[DELETE\]'
                   '|^\[READ\]',
                   l):        
        # Parse it out Ops, metric, metric value
        m = l.split(",")
        # Add a row to the table
        rowcnt = rowcnt +1
        t.append([]);
        t[rowcnt].append(sys.argv[3])  # RUNID
        t[rowcnt].append(sys.argv[4])  # DB
        t[rowcnt].append(sys.argv[5])  # WORKLOAD
        t[rowcnt].append(sys.argv[6])  # THREADS
        t[rowcnt].append(sys.argv[7])  # RECORDS
        t[rowcnt].append(m[0].strip()); #OP
        t[rowcnt].append(m[1].strip()); # METRIC
        t[rowcnt].append(m[2].strip()); # VALUE
    
# Print the table
# Loop over rows.
#for row in t:
# Loop over columns.
#    print(row)

with open(csvfile, 'w') as fout:
    writer=csv.writer(fout)
    for row in t:
        writer.writerow(row)

