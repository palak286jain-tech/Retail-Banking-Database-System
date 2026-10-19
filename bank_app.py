"""
Retail Banking Database System - Python front end (BCSE302L Review III)
Flow shown for every operation:
    User operation -> SQL/PL-SQL component -> tables involved -> result
Requires:  pip install oracledb
Run:       python bank_app.py   (see the step-by-step guide)
Needs Banking_Review2.sql and Banking_Review3.sql to have been run in the same Oracle schema.
"""
import datetime
import getpass
import oracledb


# ----------------------------------------------------------------- helpers
def connect():
    print("Press Enter to accept the value shown in [brackets].")
    lib = input("Oracle client folder for 'thick mode' (only needed for Oracle 11g; else just Enter): ").strip()
    if lib:
        oracledb.init_oracle_client(lib_dir=lib)
    user = input("Oracle username [SYSTEM]: ").strip() or "SYSTEM"
    pwd = getpass.getpass("Oracle password (typing is hidden): ")
    dsn = input("DSN host:port/service [localhost:1521/XE]: ").strip() or "localhost:1521/XE"
    return oracledb.connect(user=user, password=pwd, dsn=dsn)


def flow(operation, component, tables):
    print(f"\n  Operation : {operation}")
    print(f"  Component : {component}")
    print(f"  Tables    : {tables}")


def flush_output(cur):
    """Print whatever the PL/SQL code wrote with DBMS_OUTPUT."""
    line, status = cur.var(str), cur.var(int)
    while True:
        cur.callproc("dbms_output.get_line", (line, status))
        if status.getvalue() != 0:
            break
        print("  " + line.getvalue())


def run_proc(cur, name, args):
    """Call a stored procedure; show its messages or the database error."""
    try:
        cur.callproc(name, args)
        flush_output(cur)
        return True
    except oracledb.DatabaseError as exc:
        msg = str(exc.args[0].message).split("\n")[0]
        print(f"  Rejected by database -> {msg}")
        return False


def show_query(cur, sql, params=None):
    cur.execute(sql, params or {})
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    if not rows:
        print("  (no rows)")
        return
    widths = [max(len(c), *(len(str(r[i])) for r in rows)) for i, c in enumerate(cols)]
    print("  " + " | ".join(c.ljust(w) for c, w in zip(cols, widths)))
    print("  " + "-+-".join("-" * w for w in widths))
    for r in rows:
        print("  " + " | ".join(str(v).ljust(w) for v, w in zip(r, widths)))


def ask_int(text):
    return int(input(text).strip())


def ask_num(text):
    return float(input(text).strip())


def ask_date(text):
    return datetime.datetime.strptime(input(text + " (YYYY-MM-DD): ").strip(), "%Y-%m-%d")


# ----------------------------------------------------------------- operations
def register_customer(cur):
    flow("Register customer", "register_customer + customer_age + trg_customer_age_check", "CUSTOMER")
    cid = cur.var(int)
    args = [input("First name: "), input("Last name: "), ask_date("Date of birth"),
            input("Gender (M/F/O): ").upper(), input("Email: "), input("Phone (10 digits): "),
            input("Address: "), input("City: "), input("PAN (e.g. ABCDE1234F): ").upper(), cid]
    if run_proc(cur, "register_customer", args):
        print(f"  Result: customer_id = {int(cid.getvalue())}")


def verify_kyc(cur):
    flow("Verify / reject KYC (staff)", "verify_kyc", "CUSTOMER")
    run_proc(cur, "verify_kyc", [ask_int("Customer id: "), input("VERIFIED or REJECTED: ").upper()])


def open_account(cur):
    flow("Open account + first DEPOSIT", "open_account + trg_txn_account_status", "CUSTOMER, ACCOUNT, TRANSACTIONS")
    acc = cur.var(int)
    args = [ask_int("Customer id: "), ask_int("Branch id: "), input("Type (SAVINGS/CURRENT/SALARY): ").upper(),
            ask_num("Opening deposit: "), input("Nominee name: "), acc]
    if run_proc(cur, "open_account", args):
        print(f"  Result: account_no = {int(acc.getvalue())}")


def check_balance(cur):
    flow("Check balance", "get_balance (function)", "ACCOUNT")
    try:
        bal = cur.callfunc("get_balance", float, [ask_int("Account no: ")])
        print(f"  Result: balance = {bal:.2f}")
    except oracledb.DatabaseError as exc:
        print("  Rejected by database ->", str(exc.args[0].message).split("\n")[0])


def deposit(cur):
    flow("Deposit", "deposit_money + trg_txn_account_status", "ACCOUNT, TRANSACTIONS")
    run_proc(cur, "deposit_money", [ask_int("Account no: "), ask_num("Amount: "), "ONLINE", "Deposit via app"])


def withdraw(cur):
    flow("Withdraw", "withdraw_money + trg_account_balance_check", "ACCOUNT, TRANSACTIONS")
    run_proc(cur, "withdraw_money", [ask_int("Account no: "), ask_num("Amount: "), "ONLINE", "Withdrawal via app"])


def transfer(cur):
    flow("Transfer funds (debit + credit in one transaction)", "transfer_funds", "ACCOUNT, TRANSACTIONS")
    run_proc(cur, "transfer_funds", [ask_int("From account: "), ask_int("To account: "), ask_num("Amount: "), "ONLINE"])


def mini_statement(cur):
    flow("Mini statement (last 10 transactions)", "SELECT on TRANSACTIONS (indexed on account_no)", "TRANSACTIONS")
    show_query(cur, """
        SELECT * FROM (SELECT txn_id, TO_CHAR(txn_date,'DD-Mon-YYYY HH24:MI') AS txn_date, txn_type,
                              amount, balance_after, channel
                         FROM transactions WHERE account_no = :acc ORDER BY txn_date DESC, txn_id DESC)
         WHERE ROWNUM <= 10""", {"acc": ask_int("Account no: ")})


def issue_card(cur):
    flow("Issue card", "issue_card", "ACCOUNT, CUSTOMER, CARD")
    card = cur.var(str)
    if run_proc(cur, "issue_card", [ask_int("Account no: "), input("DEBIT or CREDIT: ").upper(), card, 50000]):
        print(f"  Result: card_no = {card.getvalue()}")


def card_status(cur):
    flow("Block / unblock card", "set_card_status", "CARD")
    run_proc(cur, "set_card_status", [input("Card no: "), input("ACTIVE or BLOCKED: ").upper()])


def apply_loan(cur):
    flow("Apply for loan", "apply_loan + calculate_emi", "LOAN")
    loan = cur.var(int)
    args = [ask_int("Customer id: "), input("Type (HOME/CAR/PERSONAL/EDUCATION): ").upper(),
            ask_num("Amount: "), ask_num("Interest rate % (1-30): "), ask_int("Tenure (months): "), loan]
    if run_proc(cur, "apply_loan", args):
        print(f"  Result: loan_id = {int(loan.getvalue())}")


def approve_loan(cur):
    flow("Approve loan + generate EMI schedule (officer)", "approve_loan + calculate_emi", "LOAN, LOAN_PAYMENT, EMPLOYEE, CUSTOMER")
    run_proc(cur, "approve_loan", [ask_int("Loan id: "), ask_int("Approving employee id: "), None])


def reject_loan(cur):
    flow("Reject loan (officer)", "reject_loan", "LOAN, EMPLOYEE")
    run_proc(cur, "reject_loan", [ask_int("Loan id: "), ask_int("Employee id: ")])


def pay_emi(cur):
    flow("Pay next EMI", "pay_emi + calc_late_fee + trg_loan_outstanding",
         "LOAN, LOAN_PAYMENT, TRANSACTIONS, ACCOUNT")
    run_proc(cur, "pay_emi", [ask_int("Loan id: "), ask_int("Pay from account no: "), "ONLINE"])


def loan_schedule(cur):
    flow("EMI schedule report", "loan_schedule_report (cursor)", "LOAN_PAYMENT, LOAN")
    run_proc(cur, "loan_schedule_report", [ask_int("Loan id: ")])


def customer_360(cur):
    flow("Customer 360 report", "customer_360 (cursors) + get_customer_total_balance + next_emi_due_date",
         "CUSTOMER, ACCOUNT, CARD, LOAN")
    run_proc(cur, "customer_360", [ask_int("Customer id: ")])


def branch_report(cur):
    flow("Branch report", "view v_branch_report", "BRANCH, EMPLOYEE, ACCOUNT")
    show_query(cur, "SELECT branch_id, branch_name, manager_name, staff, no_of_accounts, total_deposits "
                    "FROM v_branch_report ORDER BY total_deposits DESC")


def overdue_report(cur):
    flow("Overdue EMI report", "view v_overdue_emis", "LOAN, LOAN_PAYMENT, CUSTOMER")
    show_query(cur, "SELECT loan_id, customer_name, due_date, days_overdue, emi_amount, late_fee, amount_due "
                    "FROM v_overdue_emis ORDER BY days_overdue DESC")


def end_of_day(cur):
    flow("End-of-day batch", "end_of_day_batch -> apply_late_fees, mark_dormant_accounts, expire_cards (cursors)",
         "LOAN_PAYMENT, ACCOUNT, CARD")
    run_proc(cur, "end_of_day_batch", [])


def close_account(cur):
    flow("Close account", "close_account", "ACCOUNT, TRANSACTIONS, CARD")
    run_proc(cur, "close_account", [ask_int("Account no: ")])


MENU = [
    ("Register customer", register_customer), ("Verify KYC (staff)", verify_kyc),
    ("Open account", open_account), ("Check balance", check_balance),
    ("Deposit", deposit), ("Withdraw", withdraw), ("Transfer funds", transfer),
    ("Mini statement", mini_statement), ("Issue card", issue_card), ("Block/unblock card", card_status),
    ("Apply for loan", apply_loan), ("Approve loan (officer)", approve_loan), ("Reject loan (officer)", reject_loan),
    ("Pay EMI", pay_emi), ("EMI schedule", loan_schedule), ("Customer 360 report", customer_360),
    ("Branch report", branch_report), ("Overdue EMI report", overdue_report),
    ("End-of-day batch", end_of_day), ("Close account", close_account),
]


def main():
    try:
        conn = connect()
    except Exception as exc:  # connection problems: show a short message and the common fixes
        print("\nCould not connect ->", str(exc).split("\n")[0])
        print("Check: user/password, DSN (host:port/service), that the Oracle service and listener are running,")
        print("and for Oracle 11g use thick mode (give the Oracle client / instant client folder).")
        return
    cur = conn.cursor()
    cur.callproc("dbms_output.enable", [None])
    print("\nConnected to Oracle", conn.version)
    while True:
        print("\n========== RETAIL BANKING SYSTEM ==========")
        for i, (label, _) in enumerate(MENU, 1):
            print(f"{i:>2}. {label}")
        print(" 0. Exit")
        try:
            choice = int(input("Choose: ").strip())
        except ValueError:
            print("Enter a number.")
            continue
        if choice == 0:
            break
        if not 1 <= choice <= len(MENU):
            print("Invalid choice.")
            continue
        try:
            MENU[choice - 1][1](cur)
            conn.commit()
        except ValueError:
            conn.rollback()
            print("  Invalid input format, nothing was changed.")
        except oracledb.DatabaseError as exc:
            conn.rollback()
            print("  Database error ->", str(exc.args[0].message).split("\n")[0])
    cur.close()
    conn.close()
    print("Disconnected.")


if __name__ == "__main__":
    main()
