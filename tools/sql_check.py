"""用真实 SQLite 验证 user_database.dart 里的 DDL 与语句。

单元测试跑的是 InMemoryUserStore，SQL 本身测不到；
这里用 Python 内置的 sqlite3 逐条执行同样的语句，
至少保证 DDL 合法、REPLACE/裁剪语句的语义与预期一致。
"""

import sqlite3

DDL = [
    """CREATE TABLE favorites (
        item_type  TEXT NOT NULL,
        item_id    TEXT NOT NULL,
        title      TEXT NOT NULL,
        subtitle   TEXT,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (item_type, item_id)
      )""",
    """CREATE TABLE notes (
        item_type  TEXT NOT NULL,
        item_id    TEXT NOT NULL,
        title      TEXT NOT NULL,
        subtitle   TEXT,
        content    TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (item_type, item_id)
      )""",
    """CREATE TABLE recent_views (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        item_type TEXT NOT NULL,
        item_id   TEXT NOT NULL,
        title     TEXT NOT NULL,
        subtitle  TEXT,
        viewed_at INTEGER NOT NULL
      )""",
    "CREATE INDEX idx_recent_time ON recent_views(viewed_at DESC)",
    "CREATE UNIQUE INDEX idx_recent_item ON recent_views(item_type, item_id)",
]

db = sqlite3.connect(":memory:")
c = db.cursor()
for stmt in DDL:
    c.execute(stmt)
print("[OK] DDL 5 条全部执行成功")

# --- favorites: INSERT OR REPLACE 去重 ---
c.execute(
    "INSERT OR REPLACE INTO favorites VALUES (?,?,?,?,?)",
    ("function", "X", "X", "", 1),
)
c.execute(
    "INSERT OR REPLACE INTO favorites VALUES (?,?,?,?,?)",
    ("function", "X", "X2", "", 2),
)
n = c.execute("SELECT COUNT(*) FROM favorites WHERE item_id='X'").fetchone()[0]
title = c.execute("SELECT title FROM favorites WHERE item_id='X'").fetchone()[0]
assert n == 1, n
assert title == "X2", title
print("[OK] favorites 重复收藏只留一行，且快照被更新为最新")

# 同 id 不同类型是两行
c.execute(
    "INSERT OR REPLACE INTO favorites VALUES (?,?,?,?,?)",
    ("peripheral", "X", "X", "", 3),
)
n = c.execute("SELECT COUNT(*) FROM favorites WHERE item_id='X'").fetchone()[0]
assert n == 2, n
print("[OK] favorites 同 id 不同类型是两条（主键是 type+id）")

# 按时间倒序
order = [r[0] for r in c.execute(
    "SELECT item_id || ':' || item_type FROM favorites ORDER BY created_at DESC"
)]
assert order == ["X:peripheral", "X:function"], order
print("[OK] favorites 按 created_at DESC 排序")

# --- recent_views: REPLACE 把重复项提到最新 ---
for i in range(3):
    c.execute(
        "INSERT OR REPLACE INTO recent_views "
        "(item_type,item_id,title,subtitle,viewed_at) VALUES (?,?,?,?,?)",
        ("function", "A", "A", "", i * 10),
    )
c.execute(
    "INSERT OR REPLACE INTO recent_views "
    "(item_type,item_id,title,subtitle,viewed_at) VALUES (?,?,?,?,?)",
    ("function", "B", "B", "", 100),
)
rows = c.execute(
    "SELECT item_id FROM recent_views ORDER BY viewed_at DESC"
).fetchall()
assert [r[0] for r in rows] == ["B", "A"], rows
print("[OK] recent_views 同一条重复查看只留一行，且按时间倒序")

# --- recent_views: 裁剪到上限 ---
for i in range(10):
    c.execute(
        "INSERT OR REPLACE INTO recent_views "
        "(item_type,item_id,title,subtitle,viewed_at) VALUES (?,?,?,?,?)",
        ("function", "C%d" % i, "C%d" % i, "", 200 + i),
    )
c.execute(
    "DELETE FROM recent_views WHERE id NOT IN ("
    "  SELECT id FROM recent_views ORDER BY viewed_at DESC LIMIT ?"
    ")",
    (5,),
)
left = [r[0] for r in c.execute(
    "SELECT item_id FROM recent_views ORDER BY viewed_at DESC"
)]
assert len(left) == 5, left
assert left[0] == "C9", left
# 保留的是时间最新的 5 条：C5~C9（C4 及更旧的被裁掉）
assert "C5" in left and "C4" not in left, left
print("[OK] recent_views 裁剪语句保留最新的 5 条，按时间倒序：%s" % left)

# --- notes: 空内容删除 ---
c.execute("INSERT OR REPLACE INTO notes VALUES (?,?,?,?,?,?)",
          ("function", "N", "N", "", "内容", 1))
c.execute("DELETE FROM notes WHERE item_type = ? AND item_id = ?",
          ("function", "N"))
assert c.execute("SELECT COUNT(*) FROM notes").fetchone()[0] == 0
print("[OK] notes 删除语句有效")

# --- 脏数据容错：item_type 未知时不崩，只是读不出来 ---
c.execute("INSERT INTO favorites VALUES (?,?,?,?,?)",
          ("bogus_type", "Y", "Y", "", 9))
n = c.execute("SELECT COUNT(*) FROM favorites").fetchone()[0]
assert n == 3, n
print("[OK] 未知 item_type 的行能存进去（Dart 侧 UserRecord.fromRow 会跳过它）")

print("\n[sql_check] 全部通过")
