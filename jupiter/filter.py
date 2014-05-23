import sys

f1 = sys.argv[1]
f2 = sys.argv[2]

get_nusp = lambda s: int(s.strip().split(":", 1)[0])

n1 = set(map(get_nusp, open(f1)))

for line in open(f2):
	num = get_nusp(line)
	if not num in n1:
		print line.rstrip()


