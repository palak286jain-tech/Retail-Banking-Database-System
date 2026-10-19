"""
Retail Banking System - desktop GUI (BCSE302L Review III)
Run:  py -3.12 bank_gui.py
Needs: oracledb 2.x (pip install "oracledb<3"), Banking_Review2.sql + Banking_Review3.sql already run.
Every button calls a stored procedure / function / view from the database; the GUI only collects input
and shows the result, together with the flow: Operation -> Component -> Tables -> Result.
"""
import datetime
import tkinter as tk
from tkinter import ttk
import oracledb

DEFAULT_LIB = r"C:\oraclexe\app\oracle\product\11.2.0\server\bin"
NAVY, BLUE, BG, WHITE = "#0f172a", "#2563eb", "#f1f5f9", "#ffffff"
MUTED, GREEN, RED = "#64748b", "#16a34a", "#dc2626"
FONT = "Segoe UI"


# ------------------------------------------------------------------ database helper
class DB:
    def __init__(self, conn):
        self.conn, self.cur = conn, conn.cursor()
        self.cur.callproc("dbms_output.enable", [None])

    def var(self, typ):
        return self.cur.var(typ)

    def lines(self):
        out, line, st = [], self.cur.var(str), self.cur.var(int)
        while True:
            self.cur.callproc("dbms_output.get_line", (line, st))
            if st.getvalue() != 0:
                return out
            out.append(line.getvalue())

    def proc(self, name, args):
        try:
            self.cur.callproc(name, args)
            self.conn.commit()
            return self.lines()
        except Exception:
            self.conn.rollback()
            raise

    def query(self, sql, params=None):
        self.cur.execute(sql, params or {})
        cols = [d[0] for d in self.cur.description]
        return cols, [tuple("" if v is None else v for v in r) for r in self.cur.fetchall()]

    def scalar(self, sql):
        return self.query(sql)[1][0][0]


def fmt(v):
    if isinstance(v, float):
        return f"{v:,.2f}"
    if isinstance(v, datetime.datetime):
        return v.strftime("%d-%b-%Y" if not (v.hour or v.minute or v.second) else "%d-%b-%Y %H:%M")
    return str(v)


def q(db, sql, p=None):
    cols, rows = db.query(sql, p)
    return [f"{len(rows)} row(s) returned"], (cols, rows)


def out(lines):
    return lines, None


# ------------------------------------------------------------------ operations: (title, component, tables, fields, handler)
# field = (key, label, kind, default)   kind: s=text i=integer n=number d=date(YYYY-MM-DD) or a list of choices
S, I, N, D = "s", "i", "n", "d"
CH = ["BRANCH", "ONLINE", "ATM", "UPI"]

CATS = {
    "Customers": [
        ("Register", "register_customer, customer_age, trg_customer_age_check", "CUSTOMER",
         [("first", "First name", S, ""), ("last", "Last name", S, ""), ("dob", "Date of birth", D, "2000-01-15"),
          ("gender", "Gender", ["M", "F", "O"], ""), ("email", "Email", S, ""), ("phone", "Phone (10 digits)", S, ""),
          ("addr", "Address", S, ""), ("city", "City", S, ""), ("pan", "PAN (ABCDE1234F)", S, "")],
         lambda db, v: out(db.proc("register_customer", [v["first"], v["last"], v["dob"], v["gender"], v["email"],
                                                         v["phone"], v["addr"], v["city"], v["pan"].upper(), db.var(int)]))),
        ("Verify KYC", "verify_kyc", "CUSTOMER", [("id", "Customer ID", I, ""), ("st", "Decision", ["VERIFIED", "REJECTED"], "")],
         lambda db, v: out(db.proc("verify_kyc", [v["id"], v["st"]]))),
        ("Search", "SELECT on CUSTOMER", "CUSTOMER", [("q", "Customer ID / phone / PAN", S, "")],
         lambda db, v: q(db, "SELECT customer_id, first_name||' '||last_name AS name, phone, pan_no, city, kyc_status "
                             "FROM customer WHERE TO_CHAR(customer_id)=:q OR phone=:q OR pan_no=UPPER(:q)", {"q": v["q"]})),
    ],
    "Accounts": [
        ("Open account", "open_account, trg_txn_account_status", "CUSTOMER, ACCOUNT, TRANSACTIONS",
         [("cust", "Customer ID", I, ""), ("br", "Branch ID", I, "1"), ("type", "Type", ["SAVINGS", "CURRENT", "SALARY"], ""),
          ("dep", "Opening deposit", N, "5000"), ("nom", "Nominee", S, "")],
         lambda db, v: out(db.proc("open_account", [v["cust"], v["br"], v["type"], v["dep"], v["nom"], db.var(int)]))),
        ("Balance", "get_balance (function)", "ACCOUNT", [("acc", "Account no", I, "")],
         lambda db, v: ([f"Balance of {v['acc']} = Rs. {db.cur.callfunc('get_balance', float, [v['acc']]):,.2f}"], None)),
        ("Close account", "close_account", "ACCOUNT, TRANSACTIONS, CARD", [("acc", "Account no", I, "")],
         lambda db, v: out(db.proc("close_account", [v["acc"]]))),
        ("All accounts", "view v_account_summary", "ACCOUNT, CUSTOMER, BRANCH", [],
         lambda db, v: q(db, "SELECT account_no, customer_name, branch_name, account_type, balance, status "
                             "FROM v_account_summary ORDER BY account_no")),
    ],
    "Transactions": [
        ("Deposit", "deposit_money, trg_txn_account_status", "ACCOUNT, TRANSACTIONS",
         [("acc", "Account no", I, ""), ("amt", "Amount", N, ""), ("ch", "Channel", CH, "")],
         lambda db, v: out(db.proc("deposit_money", [v["acc"], v["amt"], v["ch"], "Deposit via app"]))),
        ("Withdraw", "withdraw_money, trg_account_balance_check", "ACCOUNT, TRANSACTIONS",
         [("acc", "Account no", I, ""), ("amt", "Amount", N, ""), ("ch", "Channel", CH, "")],
         lambda db, v: out(db.proc("withdraw_money", [v["acc"], v["amt"], v["ch"], "Withdrawal via app"]))),
        ("Transfer", "transfer_funds (atomic debit + credit)", "ACCOUNT, TRANSACTIONS",
         [("src", "From account", I, ""), ("dst", "To account", I, ""), ("amt", "Amount", N, "")],
         lambda db, v: out(db.proc("transfer_funds", [v["src"], v["dst"], v["amt"], "ONLINE"]))),
        ("Statement", "SELECT on TRANSACTIONS (indexed)", "TRANSACTIONS", [("acc", "Account no", I, "")],
         lambda db, v: q(db, "SELECT txn_id, TO_CHAR(txn_date,'DD-Mon-YYYY HH24:MI') AS txn_date, txn_type, amount, "
                             "balance_after, to_account_no, channel, remarks FROM (SELECT * FROM transactions "
                             "WHERE account_no=:a ORDER BY txn_id DESC) WHERE ROWNUM<=25 ORDER BY txn_id", {"a": v["acc"]})),
    ],
    "Cards": [
        ("Issue card", "issue_card", "ACCOUNT, CUSTOMER, CARD",
         [("acc", "Account no", I, ""), ("type", "Type", ["DEBIT", "CREDIT"], ""), ("lim", "Daily limit", N, "50000")],
         lambda db, v: out(db.proc("issue_card", [v["acc"], v["type"], db.var(str), v["lim"]]))),
        ("Block / Unblock", "set_card_status", "CARD", [("card", "Card number", S, ""), ("st", "Status", ["BLOCKED", "ACTIVE"], "")],
         lambda db, v: out(db.proc("set_card_status", [v["card"], v["st"]]))),
        ("Cards of account", "SELECT on CARD", "CARD", [("acc", "Account no", I, "")],
         lambda db, v: q(db, "SELECT card_no, card_type, holder_name, TO_CHAR(expiry_date,'DD-Mon-YYYY') AS expiry, "
                             "daily_limit, card_status FROM card WHERE account_no=:a", {"a": v["acc"]})),
    ],
    "Loans": [
        ("Apply", "apply_loan, calculate_emi", "LOAN",
         [("cust", "Customer ID", I, ""), ("type", "Type", ["PERSONAL", "HOME", "CAR", "EDUCATION"], ""),
          ("amt", "Amount", N, ""), ("rate", "Interest % (1-30)", N, "10"), ("m", "Tenure (months)", I, "12")],
         lambda db, v: out(db.proc("apply_loan", [v["cust"], v["type"], v["amt"], v["rate"], v["m"], db.var(int)]))),
        ("Approve", "approve_loan (EMI + schedule)", "LOAN, LOAN_PAYMENT, EMPLOYEE, CUSTOMER",
         [("loan", "Loan ID", I, ""), ("emp", "Approving employee ID", I, "114")],
         lambda db, v: out(db.proc("approve_loan", [v["loan"], v["emp"], None]))),
        ("Reject", "reject_loan", "LOAN, EMPLOYEE", [("loan", "Loan ID", I, ""), ("emp", "Employee ID", I, "114")],
         lambda db, v: out(db.proc("reject_loan", [v["loan"], v["emp"]]))),
        ("Pay EMI", "pay_emi, calc_late_fee, trg_loan_outstanding", "LOAN, LOAN_PAYMENT, TRANSACTIONS, ACCOUNT",
         [("loan", "Loan ID", I, ""), ("acc", "Pay from account", I, "")],
         lambda db, v: out(db.proc("pay_emi", [v["loan"], v["acc"], "ONLINE"]))),
        ("EMI schedule", "SELECT on LOAN_PAYMENT", "LOAN_PAYMENT, LOAN", [("loan", "Loan ID", I, "")],
         lambda db, v: q(db, "SELECT ROW_NUMBER() OVER (ORDER BY lp.payment_id) AS no, TO_CHAR(lp.due_date,'DD-Mon-YYYY') AS due_date, "
                             "lp.pay_status, l.emi_amount, lp.late_fee, TO_CHAR(lp.paid_date,'DD-Mon-YYYY') AS paid_on, lp.txn_id "
                             "FROM loan_payment lp JOIN loan l ON l.loan_id=lp.loan_id WHERE lp.loan_id=:l ORDER BY lp.payment_id",
                         {"l": v["loan"]})),
        ("Portfolio", "view v_loan_status", "LOAN, LOAN_PAYMENT, CUSTOMER", [],
         lambda db, v: q(db, "SELECT loan_id, customer_name, loan_type, principal_amt, emi_amount, outstanding_amt, status, "
                             "emis_paid, emis_pending FROM v_loan_status ORDER BY loan_id")),
    ],
    "Reports": [
        ("Branches", "view v_branch_report", "BRANCH, EMPLOYEE, ACCOUNT", [],
         lambda db, v: q(db, "SELECT branch_id, branch_name, manager_name, staff, no_of_accounts, total_deposits "
                             "FROM v_branch_report ORDER BY total_deposits DESC")),
        ("Overdue EMIs", "view v_overdue_emis", "LOAN, LOAN_PAYMENT, CUSTOMER", [],
         lambda db, v: q(db, "SELECT loan_id, customer_name, phone, loan_type, TO_CHAR(due_date,'DD-Mon-YYYY') AS due_date, "
                             "days_overdue, emi_amount, late_fee, amount_due FROM v_overdue_emis ORDER BY days_overdue DESC, loan_id")),
        ("Top customers", "view v_customer_balance", "CUSTOMER, ACCOUNT", [],
         lambda db, v: q(db, "SELECT * FROM (SELECT customer_id, customer_name, city, no_of_accounts, total_balance "
                             "FROM v_customer_balance ORDER BY total_balance DESC) WHERE ROWNUM<=10")),
        ("Monthly summary", "view v_monthly_summary", "TRANSACTIONS", [],
         lambda db, v: q(db, "SELECT txn_month, txn_count, total_credit, total_debit FROM v_monthly_summary ORDER BY txn_month")),
        ("Customer 360", "customer_360 (cursors)", "CUSTOMER, ACCOUNT, CARD, LOAN", [("id", "Customer ID", I, "1001")],
         lambda db, v: out(db.proc("customer_360", [v["id"]]))),
    ],
    "Operations": [
        ("End-of-day batch", "end_of_day_batch -> apply_late_fees, mark_dormant_accounts, expire_cards (cursors)",
         "LOAN_PAYMENT, ACCOUNT, CARD", [], lambda db, v: out(db.proc("end_of_day_batch", []))),
        ("Integrity audit", "balance vs latest balance_after", "ACCOUNT, TRANSACTIONS", [],
         lambda db, v: (lambda c, r: (["All account balances reconcile with the transaction history."], None) if not r
                        else ([f"{len(r)} mismatch(es) found"], (c, r)))(*db.query(
             "SELECT a.account_no, a.balance, t.balance_after FROM account a JOIN transactions t ON t.txn_id="
             "(SELECT MAX(t2.txn_id) FROM transactions t2 WHERE t2.account_no=a.account_no) WHERE a.balance<>t.balance_after"))),
    ],
}
ICONS = {"Dashboard": "▣", "Customers": "👤", "Accounts": "🏦", "Transactions": "💸", "Cards": "💳",
         "Loans": "📑", "Reports": "📊", "Operations": "⚙"}
TILES = [("Customers", "SELECT COUNT(*) FROM customer", "{:,}", "#2563eb"),
         ("Active accounts", "SELECT COUNT(*) FROM account WHERE status='ACTIVE'", "{:,}", "#0891b2"),
         ("Total deposits", "SELECT NVL(SUM(balance),0) FROM account", "Rs. {:,.0f}", "#16a34a"),
         ("Active loans", "SELECT COUNT(*) FROM loan WHERE status='ACTIVE'", "{:,}", "#9333ea"),
         ("Overdue EMIs", "SELECT COUNT(*) FROM v_overdue_emis", "{:,}", "#dc2626"),
         ("Transactions", "SELECT COUNT(*) FROM transactions", "{:,}", "#ea580c")]


# ------------------------------------------------------------------ application
class App:
    def __init__(self, root):
        self.root, self.db = root, None
        root.title("Retail Banking System")
        root.geometry("1300x820")
        root.minsize(1100, 700)
        root.configure(bg=BG)
        s = ttk.Style()
        s.theme_use("clam")
        s.configure("TNotebook", background=BG, borderwidth=0)
        s.configure("TNotebook.Tab", font=(FONT, 10, "bold"), padding=(14, 8), background="#e2e8f0")
        s.map("TNotebook.Tab", background=[("selected", WHITE)], foreground=[("selected", BLUE)])
        s.configure("Accent.TButton", background=BLUE, foreground="white", font=(FONT, 10, "bold"), padding=(20, 8), borderwidth=0)
        s.map("Accent.TButton", background=[("active", "#1d4ed8")])
        s.configure("Treeview", rowheight=26, font=(FONT, 10), background=WHITE, fieldbackground=WHITE, borderwidth=0)
        s.configure("Treeview.Heading", font=(FONT, 10, "bold"), background=NAVY, foreground="white", padding=6)
        s.map("Treeview.Heading", background=[("active", NAVY)])
        self.login()

    # ---------------- login
    def login(self):
        self.lf = tk.Frame(self.root, bg=NAVY)
        self.lf.pack(fill="both", expand=True)
        card = tk.Frame(self.lf, bg=WHITE, padx=38, pady=30)
        card.place(relx=.5, rely=.5, anchor="center")
        tk.Label(card, text="🏦", font=("Segoe UI Emoji", 34), bg=WHITE).pack()
        tk.Label(card, text="Retail Banking System", font=(FONT, 20, "bold"), bg=WHITE, fg=NAVY).pack()
        tk.Label(card, text="Sign in to the Oracle database", bg=WHITE, fg=MUTED).pack(pady=(0, 14))
        self.ent = {}
        for key, label, default, secret in [("lib", "Oracle client folder (needed for 11g)", DEFAULT_LIB, 0),
                                            ("user", "Username", "system", 0), ("pwd", "Password", "", 1),
                                            ("dsn", "DSN (host:port/service)", "localhost:1521/XE", 0)]:
            tk.Label(card, text=label, bg=WHITE, fg=MUTED, anchor="w").pack(fill="x")
            e = ttk.Entry(card, width=48, show="•" if secret else "")
            e.insert(0, default)
            e.pack(pady=(0, 8), ipady=3)
            self.ent[key] = e
        self.msg = tk.Label(card, text="", bg=WHITE, fg=RED, wraplength=360, justify="left")
        self.msg.pack()
        ttk.Button(card, text="Connect", style="Accent.TButton", command=self.connect).pack(fill="x", pady=(8, 0))
        self.ent["pwd"].focus()
        self.root.bind("<Return>", lambda _e: self.connect())

    def connect(self):
        e = {k: w.get().strip() for k, w in self.ent.items()}
        try:
            if e["lib"]:
                try:
                    oracledb.init_oracle_client(lib_dir=e["lib"])
                except oracledb.ProgrammingError:
                    pass  # already initialised
            conn = oracledb.connect(user=e["user"], password=e["pwd"], dsn=e["dsn"])
        except Exception as ex:
            self.msg.config(text=str(ex).split("\n")[0])
            return
        self.db, self.who = DB(conn), f"{e['user']}@{e['dsn']}"
        self.root.unbind("<Return>")
        self.lf.destroy()
        self.main()

    # ---------------- main window
    def main(self):
        side = tk.Frame(self.root, bg=NAVY, width=225)
        side.pack(side="left", fill="y")
        side.pack_propagate(False)
        tk.Label(side, text="🏦  Retail Bank", font=(FONT, 16, "bold"), bg=NAVY, fg="white", pady=24).pack()
        self.nav = {}
        for name in ICONS:
            b = tk.Button(side, text=f"  {ICONS[name]}   {name}", anchor="w", relief="flat", bd=0, bg=NAVY, fg="#cbd5e1",
                          activebackground=BLUE, activeforeground="white", font=(FONT, 11), padx=20, pady=11,
                          cursor="hand2", command=lambda n=name: self.show(n))
            b.pack(fill="x")
            self.nav[name] = b
        tk.Button(side, text="  ⏻   Disconnect", anchor="w", relief="flat", bd=0, bg=NAVY, fg="#fca5a5", font=(FONT, 11),
                  padx=20, pady=11, cursor="hand2", command=self.root.destroy).pack(side="bottom", fill="x", pady=12)

        right = tk.Frame(self.root, bg=BG)
        right.pack(side="left", fill="both", expand=True)
        head = tk.Frame(right, bg=BG)
        head.pack(fill="x", padx=24, pady=(16, 6))
        self.title = tk.Label(head, font=(FONT, 20, "bold"), bg=BG, fg=NAVY)
        self.title.pack(side="left")
        tk.Label(head, text=f"● Connected   {self.who}", bg=BG, fg=GREEN, font=(FONT, 10, "bold")).pack(side="right")
        self.top = tk.Frame(right, bg=BG)
        self.top.pack(fill="x", padx=24)

        res = tk.Frame(right, bg=WHITE)
        res.pack(fill="both", expand=True, padx=24, pady=(10, 14))
        self.trace = tk.Label(res, text="Choose an operation and press Run: the flow and result appear here.", bg="#eff6ff",
                              fg=BLUE, anchor="w", padx=12, pady=9, font=(FONT, 10, "bold"))
        self.trace.pack(fill="x")
        tf = tk.Frame(res, bg=WHITE)
        tf.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(tf, show="headings")
        vs = ttk.Scrollbar(tf, command=self.tree.yview)
        hs = ttk.Scrollbar(tf, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vs.set, xscrollcommand=hs.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        vs.grid(row=0, column=1, sticky="ns")
        hs.grid(row=1, column=0, sticky="ew")
        tf.rowconfigure(0, weight=1)
        tf.columnconfigure(0, weight=1)
        self.tree.tag_configure("odd", background="#f8fafc")
        self.log_box = tk.Text(res, height=8, font=("Consolas", 10), bg="#0f172a", fg="#e2e8f0", relief="flat", padx=10, pady=8)
        self.log_box.pack(fill="x")
        for tag, col in (("ok", "#4ade80"), ("err", "#f87171"), ("info", "#93c5fd")):
            self.log_box.tag_configure(tag, foreground=col)

        self.frames = {}
        self.build_dashboard()
        for cat, acts in CATS.items():
            nb = ttk.Notebook(self.top)
            for act in acts:
                self.build_tab(nb, act)
            self.frames[cat] = nb
        self.show("Dashboard")

    def show(self, name):
        for n, b in self.nav.items():
            b.config(bg=BLUE if n == name else NAVY, fg="white" if n == name else "#cbd5e1")
        for f in self.frames.values():
            f.pack_forget()
        self.frames[name].pack(fill="x")
        self.title.config(text=name)
        if name == "Dashboard":
            self.refresh_dashboard()
            self.show_table(*self.db.query(
                "SELECT * FROM (SELECT txn_id, TO_CHAR(txn_date,'DD-Mon-YYYY HH24:MI') AS txn_date, account_no, txn_type, "
                "amount, balance_after, channel FROM transactions ORDER BY txn_id DESC) WHERE ROWNUM<=12"))
            self.set_trace("Latest 12 transactions in the bank", None)

    # ---------------- dashboard
    def build_dashboard(self):
        f = tk.Frame(self.top, bg=BG)
        self.tiles = []
        for i, (cap, sql, pattern, color) in enumerate(TILES):
            t = tk.Frame(f, bg=WHITE)
            t.grid(row=i // 3, column=i % 3, padx=(0, 12), pady=(0, 12), sticky="ew")
            f.columnconfigure(i % 3, weight=1)
            tk.Frame(t, bg=color, width=6).pack(side="left", fill="y")
            inner = tk.Frame(t, bg=WHITE, padx=16, pady=12)
            inner.pack(side="left", fill="both", expand=True)
            val = tk.Label(inner, text="-", font=(FONT, 22, "bold"), bg=WHITE, fg=NAVY)
            val.pack(anchor="w")
            tk.Label(inner, text=cap, bg=WHITE, fg=MUTED, font=(FONT, 10)).pack(anchor="w")
            self.tiles.append((val, sql, pattern))
        self.frames["Dashboard"] = f

    def refresh_dashboard(self):
        for val, sql, pattern in self.tiles:
            try:
                val.config(text=pattern.format(self.db.scalar(sql)))
            except Exception:
                val.config(text="n/a")

    # ---------------- operation forms
    def build_tab(self, nb, act):
        title, comp, tables, fields, _ = act
        f = tk.Frame(nb, bg=WHITE, padx=18, pady=14)
        nb.add(f, text=f"  {title}  ")
        tk.Label(f, text=f"Component: {comp}      Tables: {tables}", bg=WHITE, fg=MUTED, font=(FONT, 9)).grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        widgets = {}
        for i, (key, label, kind, default) in enumerate(fields):
            r, c = divmod(i, 3)
            tk.Label(f, text=label, bg=WHITE, fg=NAVY, font=(FONT, 10)).grid(row=1 + r * 2, column=c, sticky="w", padx=8)
            if isinstance(kind, list):
                w = ttk.Combobox(f, values=kind, state="readonly", width=24)
                w.set(default or kind[0])
            else:
                w = ttk.Entry(f, width=27)
                w.insert(0, default)
            w.grid(row=2 + r * 2, column=c, padx=8, pady=(0, 10), sticky="w")
            widgets[key] = (w, kind, label)
        rows = (len(fields) + 2) // 3
        ttk.Button(f, text="Run  ▶", style="Accent.TButton", command=lambda: self.run(act, widgets)).grid(
            row=2 + rows * 2, column=0, sticky="w", padx=8, pady=(4, 0))

    def run(self, act, widgets):
        title, comp, tables, _, handler = act
        values = {}
        for key, (w, kind, label) in widgets.items():
            text = w.get().strip()
            try:
                if isinstance(kind, list) or kind == S:
                    values[key] = text
                elif kind == I:
                    values[key] = int(text)
                elif kind == N:
                    values[key] = float(text)
                else:
                    values[key] = datetime.datetime.strptime(text, "%Y-%m-%d")
            except ValueError:
                self.set_trace(f"{title}: invalid value for '{label}'", False)
                self.log(f"Invalid input for '{label}'. Dates use YYYY-MM-DD, numbers must be numeric.", "err")
                return
        self.set_trace(f"{title}   |   {comp}   |   Tables: {tables}", None)
        try:
            lines, table = handler(self.db, values)
        except oracledb.DatabaseError as ex:
            self.db.conn.rollback()
            self.set_trace(f"{title}: rejected by the database", False)
            self.log("Rejected by database -> " + str(ex.args[0].message).split("\n")[0], "err")
            return
        except Exception as ex:
            self.set_trace(f"{title}: error", False)
            self.log(str(ex), "err")
            return
        self.set_trace(f"{title}   |   {comp}   |   Tables: {tables}   ->   done", True)
        for line in lines:
            self.log(line, "ok")
        if table:
            self.show_table(*table)
        self.refresh_dashboard()

    # ---------------- output helpers
    def set_trace(self, text, ok):
        bg, fg = {True: ("#dcfce7", "#166534"), False: ("#fee2e2", "#991b1b"), None: ("#eff6ff", BLUE)}[ok]
        self.trace.config(text="  " + text, bg=bg, fg=fg)

    def log(self, msg, tag="info"):
        self.log_box.insert("end", f"[{datetime.datetime.now():%H:%M:%S}] {msg}\n", tag)
        self.log_box.see("end")

    def show_table(self, cols, rows):
        self.tree.delete(*self.tree.get_children())
        self.tree["columns"] = cols
        for i, c in enumerate(cols):
            sample = max([len(c)] + [len(fmt(r[i])) for r in rows[:40]])
            self.tree.heading(c, text=c.replace("_", " ").upper())
            self.tree.column(c, width=min(max(sample * 9 + 24, 90), 340), stretch=False)
        for n, r in enumerate(rows):
            self.tree.insert("", "end", values=[fmt(v) for v in r], tags=("odd",) if n % 2 else ())


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()
