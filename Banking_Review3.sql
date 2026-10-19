-- ============================================================================
-- BCSE302L DATABASE SYSTEMS - COURSE PROJECT - REVIEW III
-- Integrated System & Final Demonstration
-- Project : A Retail Banking Database System
-- Team    : Shreya Saravanan (24BDE0001), Palak Jain (24BDE0028), Navyaa S (24BDE0030)
--
-- PREREQUISITE : Banking_Review2.sql must have been run completely in the SAME schema.
-- This script does NOT change the Review 1 / Review 2 tables. It adds:
--   * 6 reporting views
--   * 2 functions, 9 procedures (3 use cursors), 1 trigger
--   * 7 end-to-end real-world transactions (each shows: operation, tables, component, before, after, result)
--   * reports and a final integrity audit
-- To run it again from scratch: run Banking_Review2.sql first (it rebuilds everything), then this file.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 100
SET TRIMSPOOL ON
SET FEEDBACK ON
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'DD-MON-YYYY HH24:MI:SS';
COLUMN customer_name FORMAT A22
COLUMN branch_name   FORMAT A24
COLUMN manager_name  FORMAT A16
COLUMN remarks       FORMAT A45
COLUMN holder_name   FORMAT A20
COLUMN account_no    FORMAT 999999999999
COLUMN to_account_no FORMAT 999999999999
COLUMN txn_date      FORMAT A20
COLUMN status        FORMAT A10
COLUMN city          FORMAT A14
COLUMN card_no       FORMAT A16
COLUMN object_type   FORMAT A12
SPOOL review3_output.txt

-- ============================================================================
-- PART 0 : CLEAN-UP OF REVIEW 3 OBJECTS ONLY
-- ============================================================================
BEGIN
  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('VIEW','PROCEDURE','FUNCTION','SEQUENCE','TRIGGER')
              AND object_name IN ('V_ACCOUNT_SUMMARY','V_BRANCH_REPORT','V_OVERDUE_EMIS','V_LOAN_STATUS',
                                  'V_CUSTOMER_BALANCE','V_MONTHLY_SUMMARY',
                                  'APPLY_LOAN','REJECT_LOAN','ISSUE_CARD','SET_CARD_STATUS','EXPIRE_CARDS',
                                  'CLOSE_ACCOUNT','END_OF_DAY_BATCH','CUSTOMER_360','LOAN_SCHEDULE_REPORT',
                                  'GET_CUSTOMER_TOTAL_BALANCE','NEXT_EMI_DUE_DATE','CARD_SEQ',
                                  'TRG_CUSTOMER_AGE_CHECK')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
  END LOOP;
END;
/

-- ============================================================================
-- PART 1 : NEW SEQUENCE, FUNCTIONS, TRIGGER
-- ============================================================================
CREATE SEQUENCE card_seq START WITH 13 INCREMENT BY 1 NOCACHE;

-- Function 5 : total balance of all accounts of a customer
CREATE OR REPLACE FUNCTION get_customer_total_balance (p_customer_id NUMBER) RETURN NUMBER IS
  v_total NUMBER;
BEGIN
  SELECT NVL(SUM(balance), 0) INTO v_total FROM account WHERE customer_id = p_customer_id;
  RETURN v_total;
END get_customer_total_balance;
/

-- Function 6 : due date of the next pending EMI of a loan (NULL if none)
CREATE OR REPLACE FUNCTION next_emi_due_date (p_loan_id NUMBER) RETURN DATE IS
  v_due DATE;
BEGIN
  SELECT MIN(due_date) INTO v_due FROM loan_payment WHERE loan_id = p_loan_id AND pay_status = 'PENDING';
  RETURN v_due;
END next_emi_due_date;
/

-- Trigger 6 : age >= 18 enforced for EVERY insert into CUSTOMER, even a direct INSERT (BR11)
CREATE OR REPLACE TRIGGER trg_customer_age_check
BEFORE INSERT ON customer
FOR EACH ROW
BEGIN
  IF customer_age(:NEW.dob) < 18 THEN
    RAISE_APPLICATION_ERROR(-20005, 'Customer must be at least 18 years old (BR11)');
  END IF;
END;
/

-- ============================================================================
-- PART 2 : REPORTING VIEWS
-- ============================================================================
CREATE OR REPLACE VIEW v_account_summary AS
SELECT a.account_no, c.customer_id, c.first_name || ' ' || c.last_name AS customer_name,
       b.branch_name, a.account_type, a.balance, a.min_balance, a.status
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch   b ON b.branch_id   = a.branch_id;

CREATE OR REPLACE VIEW v_branch_report AS
SELECT b.branch_id, b.branch_name, m.emp_name AS manager_name,
       (SELECT COUNT(*) FROM employee e WHERE e.branch_id = b.branch_id)                       AS staff,
       (SELECT COUNT(*) FROM account a WHERE a.branch_id = b.branch_id)                        AS no_of_accounts,
       (SELECT NVL(SUM(a.balance), 0) FROM account a WHERE a.branch_id = b.branch_id)          AS total_deposits
FROM branch b
LEFT JOIN employee m ON m.emp_id = b.manager_id;

CREATE OR REPLACE VIEW v_overdue_emis AS
SELECT l.loan_id, c.first_name || ' ' || c.last_name AS customer_name, c.phone, l.loan_type,
       lp.payment_id, lp.due_date, TRUNC(SYSDATE) - lp.due_date AS days_overdue,
       l.emi_amount, lp.late_fee, l.emi_amount + lp.late_fee AS amount_due
FROM loan l
JOIN loan_payment lp ON lp.loan_id = l.loan_id
JOIN customer c      ON c.customer_id = l.customer_id
WHERE lp.pay_status = 'PENDING' AND lp.due_date < TRUNC(SYSDATE) AND l.status = 'ACTIVE';

CREATE OR REPLACE VIEW v_loan_status AS
SELECT l.loan_id, c.first_name || ' ' || c.last_name AS customer_name, l.loan_type, l.principal_amt,
       l.interest_rate, l.emi_amount, l.outstanding_amt, l.status,
       (SELECT COUNT(*) FROM loan_payment p WHERE p.loan_id = l.loan_id AND p.pay_status IN ('PAID','LATE')) AS emis_paid,
       (SELECT COUNT(*) FROM loan_payment p WHERE p.loan_id = l.loan_id AND p.pay_status = 'PENDING')        AS emis_pending
FROM loan l
JOIN customer c ON c.customer_id = l.customer_id;

CREATE OR REPLACE VIEW v_customer_balance AS
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name, c.city,
       COUNT(a.account_no) AS no_of_accounts, NVL(SUM(a.balance), 0) AS total_balance
FROM customer c
LEFT JOIN account a ON a.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.city;

CREATE OR REPLACE VIEW v_monthly_summary AS
SELECT TO_CHAR(txn_date, 'YYYY-MM') AS txn_month, COUNT(*) AS txn_count,
       SUM(CASE WHEN txn_type IN ('DEPOSIT','TRANSFER_IN') THEN amount ELSE 0 END) AS total_credit,
       SUM(CASE WHEN txn_type IN ('WITHDRAWAL','TRANSFER_OUT','EMI_PAYMENT') THEN amount ELSE 0 END) AS total_debit
FROM transactions
GROUP BY TO_CHAR(txn_date, 'YYYY-MM');

-- ============================================================================
-- PART 3 : NEW PROCEDURES
-- ============================================================================

-- Procedure 12 : apply for a loan (FR17). Allowed before KYC; approval later checks KYC (BR6)
CREATE OR REPLACE PROCEDURE apply_loan (
  p_customer_id NUMBER, p_type VARCHAR2, p_amount NUMBER, p_rate NUMBER, p_months NUMBER,
  p_loan_id OUT NUMBER
) IS
  v_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM customer WHERE customer_id = p_customer_id;
  IF v_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20052, 'Customer ' || p_customer_id || ' not found');
  END IF;
  p_loan_id := loan_seq.NEXTVAL;
  INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months)
  VALUES (p_loan_id, p_customer_id, p_type, p_amount, p_rate, p_months);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Loan application recorded. loan_id = ' || p_loan_id || ', status = APPLIED, EMI would be ' ||
                       calculate_emi(p_amount, p_rate, p_months));
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END apply_loan;
/

-- Procedure 13 : reject a loan application (FR18, BR7)
CREATE OR REPLACE PROCEDURE reject_loan (p_loan_id NUMBER, p_emp_id NUMBER) IS
  v_status loan.status%TYPE;
  v_desig  employee.designation%TYPE;
  v_estat  employee.status%TYPE;
BEGIN
  SELECT status INTO v_status FROM loan WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_status <> 'APPLIED' THEN
    RAISE_APPLICATION_ERROR(-20022, 'Loan ' || p_loan_id || ' is ' || v_status || ', only APPLIED loans can be rejected');
  END IF;
  SELECT designation, status INTO v_desig, v_estat FROM employee WHERE emp_id = p_emp_id;
  IF v_desig NOT IN ('Loan Officer','Manager') OR v_estat <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20023, 'Only an ACTIVE Loan Officer or Manager can decide on loans (BR7)');
  END IF;
  UPDATE loan SET status = 'REJECTED', approved_by = p_emp_id WHERE loan_id = p_loan_id;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Loan ' || p_loan_id || ' rejected by employee ' || p_emp_id);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20025, 'Loan or employee not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END reject_loan;
/

-- Procedure 14 : issue a debit / credit card for an ACTIVE account (FR15)
CREATE OR REPLACE PROCEDURE issue_card (
  p_account_no NUMBER, p_type VARCHAR2, p_card_no OUT VARCHAR2, p_daily_limit NUMBER DEFAULT 50000
) IS
  v_status account.status%TYPE;
  v_name   VARCHAR2(81);
BEGIN
  SELECT a.status, UPPER(c.first_name || ' ' || c.last_name) INTO v_status, v_name
    FROM account a JOIN customer c ON c.customer_id = a.customer_id
   WHERE a.account_no = p_account_no;
  IF v_status <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20050, 'Account is ' || v_status || ': card cannot be issued');
  END IF;
  p_card_no := '40001234' || LPAD(card_seq.NEXTVAL, 8, '0');
  INSERT INTO card (card_no, account_no, card_type, holder_name, issue_date, expiry_date, daily_limit)
  VALUES (p_card_no, p_account_no, p_type, v_name, TRUNC(SYSDATE), ADD_MONTHS(TRUNC(SYSDATE), 60), p_daily_limit);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Card issued. card_no = ' || p_card_no || ', holder = ' || v_name);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20051, 'Account ' || p_account_no || ' not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END issue_card;
/

-- Procedure 15 : block / unblock a card (FR16)
CREATE OR REPLACE PROCEDURE set_card_status (p_card_no VARCHAR2, p_status VARCHAR2) IS
BEGIN
  IF p_status NOT IN ('ACTIVE','BLOCKED') THEN
    RAISE_APPLICATION_ERROR(-20053, 'Status must be ACTIVE or BLOCKED');
  END IF;
  UPDATE card SET card_status = p_status WHERE card_no = p_card_no AND card_status <> 'EXPIRED';
  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20053, 'Card not found or already expired');
  END IF;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Card ' || p_card_no || ' is now ' || p_status);
END set_card_status;
/

-- Procedure 16 (CURSOR) : mark cards whose expiry date has passed as EXPIRED (FR16)
CREATE OR REPLACE PROCEDURE expire_cards IS
  CURSOR c_cards IS
    SELECT card_no, expiry_date FROM card
     WHERE expiry_date < TRUNC(SYSDATE) AND card_status <> 'EXPIRED'
       FOR UPDATE;
  v_count NUMBER := 0;
BEGIN
  FOR r IN c_cards LOOP
    UPDATE card SET card_status = 'EXPIRED' WHERE CURRENT OF c_cards;
    v_count := v_count + 1;
    DBMS_OUTPUT.PUT_LINE('Card ' || r.card_no || ' expired on ' || TO_CHAR(r.expiry_date, 'DD-Mon-YYYY') || ' -> EXPIRED');
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_count || ' card(s) marked EXPIRED.');
END expire_cards;
/

-- Procedure 17 : close an account, pay out the balance, block its cards (FR7)
CREATE OR REPLACE PROCEDURE close_account (p_account_no NUMBER) IS
  v_acc   account%ROWTYPE;
  v_cards NUMBER;
BEGIN
  SELECT * INTO v_acc FROM account WHERE account_no = p_account_no FOR UPDATE;
  IF v_acc.status = 'CLOSED' THEN
    RAISE_APPLICATION_ERROR(-20054, 'Account is already CLOSED');
  END IF;
  IF v_acc.status = 'FROZEN' THEN
    RAISE_APPLICATION_ERROR(-20055, 'Account is FROZEN: unfreeze it before closing');
  END IF;
  UPDATE card SET card_status = 'BLOCKED' WHERE account_no = p_account_no AND card_status = 'ACTIVE';
  v_cards := SQL%ROWCOUNT;
  IF v_acc.balance > 0 THEN
    UPDATE account SET min_balance = 0, balance = 0 WHERE account_no = p_account_no;
    INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, channel, remarks)
    VALUES (txn_seq.NEXTVAL, p_account_no, 'WITHDRAWAL', v_acc.balance, 0, 'BRANCH', 'Account closure payout');
  END IF;
  UPDATE account SET status = 'CLOSED' WHERE account_no = p_account_no;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Account ' || p_account_no || ' CLOSED. Paid out ' || v_acc.balance || ', ' || v_cards || ' card(s) blocked.');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20015, 'Account ' || p_account_no || ' not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END close_account;
/

-- Procedure 18 : end-of-day batch that joins the cursor procedures of Review 2 and 3
CREATE OR REPLACE PROCEDURE end_of_day_batch IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- Step 1 : late fees on overdue EMIs ---');
  apply_late_fees;
  DBMS_OUTPUT.PUT_LINE('--- Step 2 : dormant account check ---');
  mark_dormant_accounts(180);
  DBMS_OUTPUT.PUT_LINE('--- Step 3 : expired cards ---');
  expire_cards;
  DBMS_OUTPUT.PUT_LINE('--- End of day batch complete ---');
END end_of_day_batch;
/

-- Procedure 19 (CURSORS) : complete customer report - customer, accounts, cards, loans
CREATE OR REPLACE PROCEDURE customer_360 (p_customer_id NUMBER) IS
  v_c customer%ROWTYPE;
  CURSOR c_acc IS
    SELECT account_no, account_type, balance, status FROM account
     WHERE customer_id = p_customer_id ORDER BY account_no;
  CURSOR c_card IS
    SELECT cd.card_no, cd.card_type, cd.card_status, cd.expiry_date
      FROM card cd JOIN account a ON a.account_no = cd.account_no
     WHERE a.customer_id = p_customer_id ORDER BY cd.card_no;
  CURSOR c_loan IS
    SELECT loan_id, loan_type, principal_amt, emi_amount, outstanding_amt, status FROM loan
     WHERE customer_id = p_customer_id ORDER BY loan_id;
BEGIN
  SELECT * INTO v_c FROM customer WHERE customer_id = p_customer_id;
  DBMS_OUTPUT.PUT_LINE('CUSTOMER 360 : ' || v_c.first_name || ' ' || v_c.last_name || ' (id ' || v_c.customer_id || ')');
  DBMS_OUTPUT.PUT_LINE('  City ' || v_c.city || ' | Phone ' || v_c.phone || ' | KYC ' || v_c.kyc_status ||
                       ' | Age ' || customer_age(v_c.dob));
  DBMS_OUTPUT.PUT_LINE('  ACCOUNTS (total balance ' || TO_CHAR(get_customer_total_balance(p_customer_id), 'FM99999999990.00') || ')');
  FOR r IN c_acc LOOP
    DBMS_OUTPUT.PUT_LINE('    ' || r.account_no || '  ' || RPAD(r.account_type, 8) || RPAD(r.status, 9) ||
                         TO_CHAR(r.balance, 'FM99999999990.00'));
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('  CARDS');
  FOR r IN c_card LOOP
    DBMS_OUTPUT.PUT_LINE('    ' || r.card_no || '  ' || RPAD(r.card_type, 7) || RPAD(r.card_status, 9) ||
                         'expires ' || TO_CHAR(r.expiry_date, 'DD-Mon-YYYY'));
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('  LOANS');
  FOR r IN c_loan LOOP
    DBMS_OUTPUT.PUT_LINE('    Loan ' || r.loan_id || '  ' || RPAD(r.loan_type, 10) || RPAD(r.status, 9) ||
                         'principal ' || r.principal_amt || ', EMI ' || NVL(TO_CHAR(r.emi_amount), '-') ||
                         ', outstanding ' || NVL(TO_CHAR(r.outstanding_amt), '-') ||
                         CASE WHEN r.status = 'ACTIVE'
                              THEN ', next EMI due ' || TO_CHAR(next_emi_due_date(r.loan_id), 'DD-Mon-YYYY') ||
                                   CASE WHEN next_emi_due_date(r.loan_id) < TRUNC(SYSDATE) THEN ' (OVERDUE)' ELSE '' END
                              ELSE '' END);
  END LOOP;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20056, 'Customer ' || p_customer_id || ' not found');
END customer_360;
/

-- Procedure 20 (CURSOR) : EMI schedule of a loan
CREATE OR REPLACE PROCEDURE loan_schedule_report (p_loan_id NUMBER) IS
  CURSOR c_sched IS
    SELECT lp.payment_id, lp.due_date, lp.pay_status, lp.paid_date, lp.late_fee, l.emi_amount
      FROM loan_payment lp JOIN loan l ON l.loan_id = lp.loan_id
     WHERE lp.loan_id = p_loan_id ORDER BY lp.payment_id;
  v_n NUMBER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('EMI SCHEDULE OF LOAN ' || p_loan_id);
  DBMS_OUTPUT.PUT_LINE(RPAD('NO', 4) || RPAD('DUE DATE', 14) || RPAD('STATUS', 10) || LPAD('EMI', 12) ||
                       LPAD('LATE FEE', 10) || '  PAID ON');
  FOR r IN c_sched LOOP
    v_n := v_n + 1;
    DBMS_OUTPUT.PUT_LINE(RPAD(v_n, 4) || RPAD(TO_CHAR(r.due_date, 'DD-Mon-YYYY'), 14) || RPAD(r.pay_status, 10) ||
                         LPAD(TO_CHAR(r.emi_amount, 'FM9999999990.00'), 12) ||
                         LPAD(TO_CHAR(r.late_fee, 'FM99990.00'), 10) || '  ' || TO_CHAR(r.paid_date, 'DD-Mon-YYYY'));
  END LOOP;
  IF v_n = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No EMI schedule (loan not approved yet).');
  END IF;
END loan_schedule_report;
/

PROMPT ===== Compilation errors (expect: no rows selected) =====
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

-- ============================================================================
-- PART 4 : REAL-WORLD TRANSACTIONS
-- Each transaction follows: User operation -> SQL/PL-SQL -> Database processing -> Update/Retrieval -> Result
-- ============================================================================
VARIABLE v_cust  NUMBER
VARIABLE v_acc   NUMBER
VARIABLE v_card  VARCHAR2(16)
VARIABLE v_loan  NUMBER
VARIABLE v_loan2 NUMBER

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 1 : CUSTOMER ONBOARDING (register -> KYC -> account -> card)
PROMPT # Operation : a new walk-in customer joins the bank and gets a savings account and debit card
PROMPT # Tables    : CUSTOMER, ACCOUNT, TRANSACTIONS, CARD
PROMPT # Component : register_customer, verify_kyc, open_account, issue_card (procedures),
PROMPT #             customer_age (function), trg_customer_age_check, trg_txn_account_status (triggers)
PROMPT ############################################################################
PROMPT -- BEFORE
SELECT (SELECT COUNT(*) FROM customer) AS customers, (SELECT COUNT(*) FROM account) AS accounts,
       (SELECT COUNT(*) FROM card) AS cards FROM dual;
PROMPT -- a minor is stopped by the trigger even with a direct INSERT (BR11)
INSERT INTO customer (customer_id, first_name, last_name, dob, email, phone)
VALUES (customer_seq.NEXTVAL, 'Minor', 'Test', ADD_MONTHS(TRUNC(SYSDATE), -120), 'minor.test@mail.com', '9811000022');
PROMPT -- EXECUTE
BEGIN
  register_customer('Kavya', 'Reddy', DATE '1997-05-14', 'F', 'kavya.reddy@mail.com', '9811000021',
                    '10 Gandhi Road', 'Vellore', 'PQRSK4321P', :v_cust);
  verify_kyc(:v_cust, 'VERIFIED');
  open_account(:v_cust, 1, 'SAVINGS', 10000, 'Lakshmi Reddy', :v_acc);
  issue_card(:v_acc, 'DEBIT', :v_card);
END;
/
PROMPT -- AFTER
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name, c.kyc_status,
       a.account_no, a.balance, cd.card_no, cd.card_status
FROM customer c JOIN account a ON a.customer_id = c.customer_id JOIN card cd ON cd.account_no = a.account_no
WHERE c.customer_id = :v_cust;
SELECT txn_id, txn_type, amount, balance_after, remarks FROM transactions WHERE account_no = :v_acc;
PROMPT -- RESULT : customer registered, KYC verified, account opened with first DEPOSIT row, debit card issued.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 2 : FUND TRANSFER (atomic debit + credit) AND A REJECTED TRANSFER
PROMPT # Operation : Ananya (acct 500000000004) sends 15000 to the new customer; a second transfer
PROMPT #             that would break the minimum balance is attempted
PROMPT # Tables    : ACCOUNT, TRANSACTIONS
PROMPT # Component : transfer_funds, print_statement (cursor), get_balance (function),
PROMPT #             trg_account_balance_check, ck_txn_transfer (CHECK)
PROMPT ############################################################################
PROMPT -- BEFORE
SELECT account_no, balance FROM account WHERE account_no IN (500000000004) OR account_no = :v_acc;
PROMPT -- EXECUTE
BEGIN
  transfer_funds(500000000004, :v_acc, 15000, 'ONLINE');
END;
/
PROMPT -- second transfer would leave 500 (< minimum balance 1000) -> rejected and rolled back
BEGIN
  transfer_funds(:v_acc, 500000000004, 24500, 'ONLINE');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- AFTER
SELECT account_no, balance FROM account WHERE account_no IN (500000000004) OR account_no = :v_acc;
BEGIN
  print_statement(:v_acc, TRUNC(SYSDATE), TRUNC(SYSDATE));
END;
/
PROMPT -- RESULT : two linked TRANSFER rows, balances moved together; the failed transfer left nothing behind.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 3 : LOAN LIFECYCLE (apply -> approve -> EMI schedule -> pay all EMIs -> auto close)
PROMPT # Operation : Neelam (customer 1010) takes a 30000 personal loan for 3 months and repays it
PROMPT # Tables    : LOAN, LOAN_PAYMENT, TRANSACTIONS, ACCOUNT
PROMPT # Component : apply_loan, approve_loan, pay_emi, loan_schedule_report (procedures),
PROMPT #             calculate_emi, calc_late_fee (functions), trg_loan_outstanding (trigger)
PROMPT ############################################################################
BEGIN
  apply_loan(1010, 'PERSONAL', 30000, 12, 3, :v_loan);
END;
/
PROMPT -- BEFORE (application only, no schedule yet)
SELECT loan_id, status, principal_amt, emi_amount, outstanding_amt, approved_by FROM loan WHERE loan_id = :v_loan;
PROMPT -- EXECUTE : approval by Loan Officer 114 creates EMI and 3 schedule rows
BEGIN
  approve_loan(:v_loan, 114);
END;
/
BEGIN
  loan_schedule_report(:v_loan);
END;
/
PROMPT -- pay the 3 EMIs from the loan holder's own account
BEGIN
  pay_emi(:v_loan, 500000000010, 'ONLINE');
  pay_emi(:v_loan, 500000000010, 'ONLINE');
  pay_emi(:v_loan, 500000000010, 'ONLINE');
END;
/
PROMPT -- AFTER
SELECT loan_id, status, emi_amount, outstanding_amt FROM loan WHERE loan_id = :v_loan;
BEGIN
  loan_schedule_report(:v_loan);
END;
/
SELECT lp.payment_id, lp.pay_status, lp.amount_paid, lp.late_fee, t.txn_id, t.txn_type, t.amount, t.balance_after
FROM loan_payment lp JOIN transactions t ON t.txn_id = lp.txn_id
WHERE lp.loan_id = :v_loan ORDER BY lp.payment_id;
PROMPT -- an EMI_PAYMENT transaction is traceable to its instalment; the closed loan accepts no more EMIs
BEGIN
  pay_emi(:v_loan, 500000000010, 'ONLINE');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- RESULT : outstanding fell to 0 through the trigger and the loan status changed to CLOSED automatically.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 4 : BUSINESS RULES ON LOANS (KYC rule, approver rule, rejection)
PROMPT # Operation : customer 1012 (KYC REJECTED) applies for a car loan
PROMPT # Tables    : LOAN, CUSTOMER, EMPLOYEE
PROMPT # Component : apply_loan, approve_loan, reject_loan, ck_loan_outstanding_null (CHECK)
PROMPT ############################################################################
BEGIN
  apply_loan(1012, 'CAR', 500000, 10, 36, :v_loan2);
END;
/
PROMPT -- the application is recorded (BR6 allows this) but cannot be approved
BEGIN
  approve_loan(:v_loan2, 114);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- a Clerk (113) cannot decide on loans (BR7)
BEGIN
  reject_loan(:v_loan2, 113);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
BEGIN
  reject_loan(:v_loan2, 114);
END;
/
SELECT loan_id, customer_id, status, approved_by, emi_amount, outstanding_amt FROM loan WHERE loan_id = :v_loan2;
PROMPT -- RESULT : application recorded, approval blocked by BR6, rejected by an authorised officer, no EMI schedule created.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 5 : ACCOUNT SECURITY (block card, freeze account, reject transactions, restore)
PROMPT # Operation : the new customer reports a lost card; the branch freezes the account, then restores it
PROMPT # Tables    : CARD, ACCOUNT, TRANSACTIONS
PROMPT # Component : set_card_status, deposit_money, withdraw_money, trg_txn_account_status (trigger)
PROMPT ############################################################################
BEGIN
  set_card_status(:v_card, 'BLOCKED');
END;
/
UPDATE account SET status = 'FROZEN' WHERE account_no = :v_acc;
COMMIT;
SELECT a.account_no, a.status AS account_status, cd.card_status FROM account a JOIN card cd ON cd.account_no = a.account_no WHERE a.account_no = :v_acc;
PROMPT -- transactions on the FROZEN account are rejected
BEGIN
  withdraw_money(:v_acc, 500, 'ATM', 'Attempt on frozen account');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
BEGIN
  transfer_funds(500000000004, :v_acc, 100, 'ONLINE');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- restore the account and card, then a deposit succeeds
UPDATE account SET status = 'ACTIVE' WHERE account_no = :v_acc;
COMMIT;
BEGIN
  set_card_status(:v_card, 'ACTIVE');
  deposit_money(:v_acc, 2000, 'BRANCH', 'Deposit after unfreeze');
END;
/
SELECT a.account_no, a.status AS account_status, a.balance, cd.card_status FROM account a JOIN card cd ON cd.account_no = a.account_no WHERE a.account_no = :v_acc;
PROMPT -- RESULT : frozen account refused every debit and credit; after restoration normal operation resumed.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 6 : END-OF-DAY BATCH (cursor processing of many records)
PROMPT # Operation : the bank's nightly job charges late fees, flags dormant accounts, expires old cards
PROMPT # Tables    : LOAN_PAYMENT, LOAN, ACCOUNT, TRANSACTIONS, CARD
PROMPT # Component : end_of_day_batch -> apply_late_fees, mark_dormant_accounts, expire_cards (all use cursors)
PROMPT ############################################################################
PROMPT -- set-up: a card whose expiry date is already over but still marked ACTIVE
INSERT INTO card VALUES ('4000123400000099', 500000000012, 'DEBIT', 'ROHAN MEHTA', DATE '2020-01-01', TRUNC(SYSDATE) - 1, 20000, 'ACTIVE');
COMMIT;
PROMPT -- BEFORE
SELECT COUNT(*) AS overdue_emis_with_fee FROM v_overdue_emis WHERE late_fee > 0;
SELECT card_no, card_status, expiry_date FROM card WHERE card_no = '4000123400000099';
PROMPT -- EXECUTE
BEGIN
  end_of_day_batch;
END;
/
PROMPT -- AFTER
SELECT card_no, card_status, expiry_date FROM card WHERE card_no = '4000123400000099';
SELECT status, COUNT(*) AS accounts FROM account GROUP BY status ORDER BY status;
PROMPT -- RESULT : fees refreshed on overdue EMIs, stale accounts flagged, expired card marked EXPIRED.

PROMPT
PROMPT ############################################################################
PROMPT # TRANSACTION 7 : ACCOUNT CLOSURE (end of the customer lifecycle)
PROMPT # Operation : the new customer closes the savings account
PROMPT # Tables    : ACCOUNT, TRANSACTIONS, CARD
PROMPT # Component : close_account, customer_360 (report), trg_account_balance_check, trg_txn_account_status
PROMPT ############################################################################
PROMPT -- BEFORE
BEGIN
  customer_360(:v_cust);
END;
/
PROMPT -- EXECUTE
BEGIN
  close_account(:v_acc);
END;
/
PROMPT -- AFTER
BEGIN
  customer_360(:v_cust);
END;
/
SELECT txn_id, txn_type, amount, balance_after, remarks FROM transactions WHERE account_no = :v_acc ORDER BY txn_id;
PROMPT -- a closed account accepts no more transactions
BEGIN
  deposit_money(:v_acc, 1000, 'BRANCH', 'After closure');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- RESULT : balance paid out through a WITHDRAWAL row, account CLOSED, cards BLOCKED, history retained.

-- ============================================================================
-- PART 5 : OUTPUT AND REPORTS
-- ============================================================================
PROMPT
PROMPT ===== REPORT 1 : Branch-wise deposits and staff =====
SELECT * FROM v_branch_report ORDER BY total_deposits DESC;

PROMPT ===== REPORT 2 : Account summary =====
SELECT * FROM v_account_summary ORDER BY account_no;

PROMPT ===== REPORT 3 : Top 5 customers by total balance =====
SELECT * FROM (SELECT customer_id, customer_name, city, no_of_accounts, total_balance
               FROM v_customer_balance ORDER BY total_balance DESC)
WHERE ROWNUM <= 5;

PROMPT ===== REPORT 4 : Loan portfolio status =====
SELECT * FROM v_loan_status ORDER BY loan_id;

PROMPT ===== REPORT 5 : Overdue EMIs (collection list) =====
SELECT loan_id, customer_name, phone, loan_type, due_date, days_overdue, emi_amount, late_fee, amount_due
FROM v_overdue_emis ORDER BY days_overdue DESC, loan_id;

PROMPT ===== REPORT 6 : Month-wise bank transaction summary =====
SELECT * FROM v_monthly_summary ORDER BY txn_month;

PROMPT ===== REPORT 7 : Transaction mix by type =====
SELECT txn_type, COUNT(*) AS txn_count, SUM(amount) AS total_amount
FROM transactions GROUP BY txn_type ORDER BY total_amount DESC;

PROMPT ===== REPORT 8 : Customer 360 view of customer 1001 =====
BEGIN
  customer_360(1001);
END;
/

-- ============================================================================
-- PART 6 : FINAL INTEGRITY AUDIT (every query below should return "no rows selected" or 0)
-- ============================================================================
PROMPT ===== AUDIT 1 : account balance differs from the latest balance_after (expect none) =====
SELECT a.account_no, a.balance, t.balance_after
FROM account a
JOIN transactions t ON t.txn_id = (SELECT MAX(t2.txn_id) FROM transactions t2 WHERE t2.account_no = a.account_no)
WHERE a.balance <> t.balance_after;

PROMPT ===== AUDIT 2 : EMI_PAYMENT transactions not linked to an instalment (expect none) =====
SELECT t.txn_id, t.account_no, t.amount
FROM transactions t
WHERE t.txn_type = 'EMI_PAYMENT'
  AND NOT EXISTS (SELECT 1 FROM loan_payment lp WHERE lp.txn_id = t.txn_id);

PROMPT ===== AUDIT 3 : open accounts below their minimum balance (expect none) =====
SELECT account_no, balance, min_balance FROM account WHERE status <> 'CLOSED' AND balance < min_balance;

PROMPT ===== AUDIT 4 : transfer rows whose partner row is missing (expect none) =====
SELECT t.txn_id, t.account_no, t.to_account_no, t.txn_type
FROM transactions t
WHERE t.txn_type = 'TRANSFER_OUT'
  AND NOT EXISTS (SELECT 1 FROM transactions i
                  WHERE i.txn_type = 'TRANSFER_IN' AND i.account_no = t.to_account_no
                    AND i.to_account_no = t.account_no AND i.amount = t.amount
                    AND i.txn_date >= t.txn_date AND i.txn_date <= t.txn_date + INTERVAL '5' SECOND);

PROMPT ===== AUDIT 5 : branch managers who are not Managers of their own branch (expect none) =====
SELECT b.branch_id, b.manager_id FROM branch b JOIN employee e ON e.emp_id = b.manager_id
WHERE e.branch_id <> b.branch_id OR e.designation <> 'Manager';

PROMPT ===== AUDIT 6 : project object inventory (expect TABLE 8, VIEW 6, SEQUENCE 6, FUNCTION 6, PROCEDURE 20, TRIGGER 6) =====
SELECT object_type, COUNT(*) AS total FROM user_objects
WHERE (object_type = 'TABLE' AND object_name IN ('BRANCH','EMPLOYEE','CUSTOMER','ACCOUNT','TRANSACTIONS','CARD','LOAN','LOAN_PAYMENT'))
   OR (object_type IN ('VIEW','SEQUENCE','FUNCTION','PROCEDURE','TRIGGER') AND object_name IN ('V_ACCOUNT_SUMMARY','V_BRANCH_REPORT','V_OVERDUE_EMIS','V_LOAN_STATUS','V_CUSTOMER_BALANCE','V_MONTHLY_SUMMARY','CUSTOMER_SEQ','ACCOUNT_SEQ','TXN_SEQ','LOAN_SEQ','PAYMENT_SEQ','CARD_SEQ','CALCULATE_EMI','GET_BALANCE','CUSTOMER_AGE','CALC_LATE_FEE','GET_CUSTOMER_TOTAL_BALANCE','NEXT_EMI_DUE_DATE','REGISTER_CUSTOMER','VERIFY_KYC','OPEN_ACCOUNT','DEPOSIT_MONEY','WITHDRAW_MONEY','TRANSFER_FUNDS','APPROVE_LOAN','PAY_EMI','MARK_DORMANT_ACCOUNTS','APPLY_LATE_FEES','PRINT_STATEMENT','APPLY_LOAN','REJECT_LOAN','ISSUE_CARD','SET_CARD_STATUS','EXPIRE_CARDS','CLOSE_ACCOUNT','END_OF_DAY_BATCH','CUSTOMER_360','LOAN_SCHEDULE_REPORT','TRG_TXN_IMMUTABLE','TRG_ACCOUNT_BALANCE_CHECK','TRG_TXN_ACCOUNT_STATUS','TRG_LOAN_OUTSTANDING','TRG_BRANCH_MANAGER_CHECK','TRG_CUSTOMER_AGE_CHECK'))
GROUP BY object_type ORDER BY object_type;
PROMPT ===== AUDIT 7 : invalid project objects (expect 0) =====
SELECT COUNT(*) AS invalid_objects FROM user_objects
WHERE status <> 'VALID'
  AND object_name IN ('BRANCH','EMPLOYEE','CUSTOMER','ACCOUNT','TRANSACTIONS','CARD','LOAN','LOAN_PAYMENT','V_ACCOUNT_SUMMARY','V_BRANCH_REPORT','V_OVERDUE_EMIS','V_LOAN_STATUS','V_CUSTOMER_BALANCE','V_MONTHLY_SUMMARY','CUSTOMER_SEQ','ACCOUNT_SEQ','TXN_SEQ','LOAN_SEQ','PAYMENT_SEQ','CARD_SEQ','CALCULATE_EMI','GET_BALANCE','CUSTOMER_AGE','CALC_LATE_FEE','GET_CUSTOMER_TOTAL_BALANCE','NEXT_EMI_DUE_DATE','REGISTER_CUSTOMER','VERIFY_KYC','OPEN_ACCOUNT','DEPOSIT_MONEY','WITHDRAW_MONEY','TRANSFER_FUNDS','APPROVE_LOAN','PAY_EMI','MARK_DORMANT_ACCOUNTS','APPLY_LATE_FEES','PRINT_STATEMENT','APPLY_LOAN','REJECT_LOAN','ISSUE_CARD','SET_CARD_STATUS','EXPIRE_CARDS','CLOSE_ACCOUNT','END_OF_DAY_BATCH','CUSTOMER_360','LOAN_SCHEDULE_REPORT','TRG_TXN_IMMUTABLE','TRG_ACCOUNT_BALANCE_CHECK','TRG_TXN_ACCOUNT_STATUS','TRG_LOAN_OUTSTANDING','TRG_BRANCH_MANAGER_CHECK','TRG_CUSTOMER_AGE_CHECK');

SPOOL OFF
-- ============================== END OF REVIEW III SCRIPT ==============================
