import sqlite3
conn=sqlite3.connect(r"C:\Users\aakash09\Desktop\sol_mvp\backend\db\companion.db")
for row in conn.execute("SELECT name, type, sql FROM sqlite_master WHERE type IN ('table','index') ORDER BY type, name"):
    print('---', row[1], row[0], '---')
    print(row[2])
