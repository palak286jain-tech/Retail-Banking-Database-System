-- ============================================================================
-- BCSE302L DATABASE SYSTEMS - COURSE PROJECT - REVIEW II (Database Implementation)
-- Project : A Retail Banking Database System
-- Team    : Shreya Saravanan (24BDE0001), Palak Jain (24BDE0028), Navyaa S (24BDE0030)
-- Run in  : Oracle SQL*Plus  (copy-paste the whole file, or  @Banking_Review2.sql)
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 220
SET PAGESIZE 100
SET TRIMSPOOL ON
SET FEEDBACK ON
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'DD-MON-YYYY HH24:MI:SS';
COLUMN customer_name FORMAT A22
COLUMN branch_name   FORMAT A24
COLUMN manager_name  FORMAT A18
COLUMN emp_name      FORMAT A18
COLUMN remarks       FORMAT A48
COLUMN email         FORMAT A32
COLUMN holder_name   FORMAT A20
COLUMN account_no    FORMAT 999999999999
COLUMN to_account_no FORMAT 999999999999
COLUMN txn_date      FORMAT A20
COLUMN trigger_name  FORMAT A28
COLUMN table_name    FORMAT A16
COLUMN triggering_event FORMAT A18
COLUMN object_name   FORMAT A26
COLUMN object_type   FORMAT A12
COLUMN status        FORMAT A10
COLUMN city          FORMAT A14
COLUMN address       FORMAT A20
COLUMN first_name    FORMAT A12
COLUMN last_name     FORMAT A12
SPOOL review2_output.txt

-- ============================================================================
-- PART 0 : CLEAN-UP (so the script can be re-run safely)
-- ============================================================================
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('LOAN_PAYMENT','LOAN','CARD','TRANSACTIONS','ACCOUNT','CUSTOMER','EMPLOYEE','BRANCH')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('CUSTOMER_SEQ','ACCOUNT_SEQ','TXN_SEQ','LOAN_SEQ','PAYMENT_SEQ')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
  FOR o IN (SELECT object_name, object_type FROM user_objects
            WHERE object_type IN ('PROCEDURE','FUNCTION')
              AND object_name IN ('CALCULATE_EMI','GET_BALANCE','CUSTOMER_AGE','CALC_LATE_FEE',
                                  'REGISTER_CUSTOMER','VERIFY_KYC','OPEN_ACCOUNT','DEPOSIT_MONEY',
                                  'WITHDRAW_MONEY','TRANSFER_FUNDS','APPROVE_LOAN','PAY_EMI',
                                  'MARK_DORMANT_ACCOUNTS','APPLY_LATE_FEES','PRINT_STATEMENT')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
  END LOOP;
END;
/

-- ============================================================================
-- PART 1 : DDL - TABLES, CONSTRAINTS, INDEXES, SEQUENCES
-- (Oracle's default foreign-key behaviour is NO ACTION, i.e. it blocks deleting a
--  parent that still has children - this is the RESTRICT behaviour of Review 1.)
-- ============================================================================

-- Table 1 : BRANCH (manager_id FK is added after EMPLOYEE exists - circular reference)
CREATE TABLE branch (
  branch_id    NUMBER(4)    CONSTRAINT pk_branch PRIMARY KEY,
  branch_name  VARCHAR2(60) NOT NULL,
  ifsc_code    VARCHAR2(11) NOT NULL CONSTRAINT uq_branch_ifsc UNIQUE,
  city         VARCHAR2(40) NOT NULL,
  state        VARCHAR2(40) NOT NULL,
  phone        VARCHAR2(10) CONSTRAINT ck_branch_phone CHECK (REGEXP_LIKE(phone, '^[0-9]{10}$')),
  manager_id   NUMBER(5)    CONSTRAINT uq_branch_manager UNIQUE
);

-- Table 2 : EMPLOYEE
CREATE TABLE employee (
  emp_id       NUMBER(5)    CONSTRAINT pk_employee PRIMARY KEY,
  branch_id    NUMBER(4)    NOT NULL CONSTRAINT fk_emp_branch REFERENCES branch(branch_id),
  emp_name     VARCHAR2(60) NOT NULL,
  designation  VARCHAR2(20) NOT NULL
               CONSTRAINT ck_emp_desig CHECK (designation IN ('Teller','Clerk','Loan Officer','Manager','Auditor')),
  email        VARCHAR2(80) NOT NULL CONSTRAINT uq_emp_email UNIQUE,
  phone        VARCHAR2(10) NOT NULL CONSTRAINT ck_emp_phone CHECK (REGEXP_LIKE(phone, '^[0-9]{10}$')),
  salary       NUMBER(10,2) CONSTRAINT ck_emp_salary CHECK (salary > 0),
  hire_date    DATE         DEFAULT SYSDATE,
  status       VARCHAR2(10) DEFAULT 'ACTIVE' CONSTRAINT ck_emp_status CHECK (status IN ('ACTIVE','INACTIVE'))
);

ALTER TABLE branch ADD CONSTRAINT fk_branch_manager FOREIGN KEY (manager_id) REFERENCES employee(emp_id);

-- Table 3 : CUSTOMER
CREATE TABLE customer (
  customer_id  NUMBER(6)    CONSTRAINT pk_customer PRIMARY KEY,
  first_name   VARCHAR2(40) NOT NULL,
  last_name    VARCHAR2(40),
  dob          DATE         NOT NULL,
  gender       CHAR(1)      CONSTRAINT ck_cust_gender CHECK (gender IN ('M','F','O')),
  email        VARCHAR2(80) NOT NULL CONSTRAINT uq_cust_email UNIQUE,
  phone        VARCHAR2(10) NOT NULL CONSTRAINT uq_cust_phone UNIQUE
               CONSTRAINT ck_cust_phone CHECK (REGEXP_LIKE(phone, '^[0-9]{10}$')),
  address      VARCHAR2(120),
  city         VARCHAR2(40),
  pan_no       CHAR(10)     CONSTRAINT uq_cust_pan UNIQUE
               CONSTRAINT ck_cust_pan CHECK (REGEXP_LIKE(pan_no, '^[A-Z]{5}[0-9]{4}[A-Z]$')),
  kyc_status   VARCHAR2(10) DEFAULT 'PENDING'
               CONSTRAINT ck_cust_kyc CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED')),
  created_on   DATE         DEFAULT SYSDATE
);

-- Table 4 : ACCOUNT
CREATE TABLE account (
  account_no    NUMBER(12)   CONSTRAINT pk_account PRIMARY KEY,
  customer_id   NUMBER(6)    NOT NULL CONSTRAINT fk_acc_customer REFERENCES customer(customer_id),
  branch_id     NUMBER(4)    NOT NULL CONSTRAINT fk_acc_branch REFERENCES branch(branch_id),
  account_type  VARCHAR2(10) NOT NULL CONSTRAINT ck_acc_type CHECK (account_type IN ('SAVINGS','CURRENT','SALARY')),
  balance       NUMBER(14,2) DEFAULT 0 CONSTRAINT ck_acc_balance CHECK (balance >= 0),
  min_balance   NUMBER(10,2) DEFAULT 1000 CONSTRAINT ck_acc_minbal CHECK (min_balance >= 0),
  opened_on     DATE         DEFAULT SYSDATE,
  status        VARCHAR2(10) DEFAULT 'ACTIVE'
                CONSTRAINT ck_acc_status CHECK (status IN ('ACTIVE','DORMANT','FROZEN','CLOSED')),
  nominee_name  VARCHAR2(60)
);

-- Table 5 : TRANSACTIONS
CREATE TABLE transactions (
  txn_id         NUMBER(10)   CONSTRAINT pk_transactions PRIMARY KEY,
  account_no     NUMBER(12)   NOT NULL CONSTRAINT fk_txn_account REFERENCES account(account_no),
  txn_type       VARCHAR2(12) NOT NULL
                 CONSTRAINT ck_txn_type CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER_OUT','TRANSFER_IN','EMI_PAYMENT')),
  amount         NUMBER(12,2) NOT NULL CONSTRAINT ck_txn_amount CHECK (amount > 0),
  txn_date       TIMESTAMP    DEFAULT SYSTIMESTAMP,
  balance_after  NUMBER(14,2) NOT NULL CONSTRAINT ck_txn_balafter CHECK (balance_after >= 0),
  to_account_no  NUMBER(12)   CONSTRAINT fk_txn_toaccount REFERENCES account(account_no),
  channel        VARCHAR2(10) DEFAULT 'BRANCH' CONSTRAINT ck_txn_channel CHECK (channel IN ('BRANCH','ATM','ONLINE','UPI')),
  remarks        VARCHAR2(100),
  CONSTRAINT ck_txn_transfer CHECK (
        (txn_type IN ('TRANSFER_OUT','TRANSFER_IN') AND to_account_no IS NOT NULL AND to_account_no <> account_no)
     OR (txn_type IN ('DEPOSIT','WITHDRAWAL','EMI_PAYMENT') AND to_account_no IS NULL))
);

-- Table 6 : CARD
CREATE TABLE card (
  card_no      VARCHAR2(16) CONSTRAINT pk_card PRIMARY KEY CONSTRAINT ck_card_no CHECK (REGEXP_LIKE(card_no, '^[0-9]{16}$')),
  account_no   NUMBER(12)   NOT NULL CONSTRAINT fk_card_account REFERENCES account(account_no),
  card_type    VARCHAR2(6)  NOT NULL CONSTRAINT ck_card_type CHECK (card_type IN ('DEBIT','CREDIT')),
  holder_name  VARCHAR2(60) NOT NULL,
  issue_date   DATE         DEFAULT SYSDATE,
  expiry_date  DATE         NOT NULL,
  daily_limit  NUMBER(8)    DEFAULT 50000 CONSTRAINT ck_card_limit CHECK (daily_limit > 0),
  card_status  VARCHAR2(10) DEFAULT 'ACTIVE' CONSTRAINT ck_card_status CHECK (card_status IN ('ACTIVE','BLOCKED','EXPIRED')),
  CONSTRAINT ck_card_dates CHECK (expiry_date > issue_date)
);

-- Table 7 : LOAN
CREATE TABLE loan (
  loan_id          NUMBER(6)    CONSTRAINT pk_loan PRIMARY KEY,
  customer_id      NUMBER(6)    NOT NULL CONSTRAINT fk_loan_customer REFERENCES customer(customer_id),
  approved_by      NUMBER(5)    CONSTRAINT fk_loan_approver REFERENCES employee(emp_id),
  loan_type        VARCHAR2(10) NOT NULL CONSTRAINT ck_loan_type CHECK (loan_type IN ('HOME','CAR','PERSONAL','EDUCATION')),
  principal_amt    NUMBER(12,2) NOT NULL CONSTRAINT ck_loan_principal CHECK (principal_amt > 0),
  interest_rate    NUMBER(4,2)  NOT NULL CONSTRAINT ck_loan_rate CHECK (interest_rate BETWEEN 1 AND 30),
  tenure_months    NUMBER(3)    NOT NULL CONSTRAINT ck_loan_tenure CHECK (tenure_months > 0),
  emi_amount       NUMBER(10,2),
  applied_on       DATE         DEFAULT SYSDATE,
  start_date       DATE,
  outstanding_amt  NUMBER(12,2) CONSTRAINT ck_loan_outstanding CHECK (outstanding_amt >= 0),
  status           VARCHAR2(10) DEFAULT 'APPLIED' NOT NULL
                   CONSTRAINT ck_loan_status CHECK (status IN ('APPLIED','APPROVED','ACTIVE','CLOSED','REJECTED')),
  CONSTRAINT ck_loan_outstanding_null CHECK (status IN ('APPLIED','REJECTED') OR outstanding_amt IS NOT NULL)
);

-- Table 8 : LOAN_PAYMENT
CREATE TABLE loan_payment (
  payment_id   NUMBER(8)    CONSTRAINT pk_loan_payment PRIMARY KEY,
  loan_id      NUMBER(6)    NOT NULL CONSTRAINT fk_lp_loan REFERENCES loan(loan_id),
  txn_id       NUMBER(10)   CONSTRAINT fk_lp_txn REFERENCES transactions(txn_id)
                            CONSTRAINT uq_lp_txn UNIQUE,
  due_date     DATE         NOT NULL,
  paid_date    DATE,
  amount_paid  NUMBER(10,2) DEFAULT 0 CONSTRAINT ck_lp_amount CHECK (amount_paid >= 0),
  late_fee     NUMBER(8,2)  DEFAULT 0 CONSTRAINT ck_lp_latefee CHECK (late_fee >= 0),
  pay_status   VARCHAR2(10) DEFAULT 'PENDING' CONSTRAINT ck_lp_status CHECK (pay_status IN ('PENDING','PAID','LATE')),
  CONSTRAINT ck_lp_br16 CHECK (
        (pay_status = 'PENDING' AND txn_id IS NULL AND paid_date IS NULL AND amount_paid = 0)
     OR (pay_status IN ('PAID','LATE') AND txn_id IS NOT NULL AND paid_date IS NOT NULL AND amount_paid > 0))
);


-- Sanity check : must show 8 tables and 5 sequences. If not, STOP and read the FIRST error above.
SELECT COUNT(*) AS tables_created FROM user_tables
WHERE table_name IN ('BRANCH','EMPLOYEE','CUSTOMER','ACCOUNT','TRANSACTIONS','CARD','LOAN','LOAN_PAYMENT');

-- Indexes on frequently searched columns
CREATE INDEX idx_txn_account   ON transactions(account_no);
CREATE INDEX idx_txn_date      ON transactions(txn_date);
CREATE INDEX idx_acc_customer  ON account(customer_id);
CREATE INDEX idx_acc_branch    ON account(branch_id);
CREATE INDEX idx_loan_customer ON loan(customer_id);
CREATE INDEX idx_lp_loan_due   ON loan_payment(loan_id, due_date);

-- Sequences (seed data below uses explicit ids; sequences start after them)
CREATE SEQUENCE customer_seq START WITH 1013         INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE account_seq  START WITH 500000000013 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE txn_seq      START WITH 1            INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE loan_seq     START WITH 11           INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE payment_seq  START WITH 1            INCREMENT BY 1 NOCACHE;

-- ============================================================================
-- PART 2 : FUNCTIONS
-- ============================================================================

-- Function 1 : EMI by the reducing-balance formula (FR19)
CREATE OR REPLACE FUNCTION calculate_emi (
  p_principal NUMBER, p_rate NUMBER, p_months NUMBER
) RETURN NUMBER DETERMINISTIC IS
  v_r NUMBER;
BEGIN
  IF p_principal <= 0 OR p_months <= 0 THEN
    RAISE_APPLICATION_ERROR(-20040, 'Principal and tenure must be positive');
  END IF;
  v_r := p_rate / 12 / 100;
  IF v_r = 0 THEN
    RETURN ROUND(p_principal / p_months, 2);
  END IF;
  RETURN ROUND(p_principal * v_r * POWER(1 + v_r, p_months) / (POWER(1 + v_r, p_months) - 1), 2);
END calculate_emi;
/

-- Function 2 : current balance of an account (FR6)
CREATE OR REPLACE FUNCTION get_balance (p_account_no NUMBER) RETURN NUMBER IS
  v_bal account.balance%TYPE;
BEGIN
  SELECT balance INTO v_bal FROM account WHERE account_no = p_account_no;
  RETURN v_bal;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20015, 'Account ' || p_account_no || ' not found');
END get_balance;
/

-- Function 3 : age in completed years (BR11)
CREATE OR REPLACE FUNCTION customer_age (p_dob DATE) RETURN NUMBER IS
BEGIN
  RETURN TRUNC(MONTHS_BETWEEN(SYSDATE, p_dob) / 12);
END customer_age;
/

-- Function 4 : late fee = 2% of the EMI if paid/pending after the due date (BR9)
CREATE OR REPLACE FUNCTION calc_late_fee (p_emi NUMBER, p_due_date DATE) RETURN NUMBER IS
BEGIN
  IF TRUNC(SYSDATE) > p_due_date THEN
    RETURN ROUND(p_emi * 0.02, 2);
  END IF;
  RETURN 0;
END calc_late_fee;
/

-- ============================================================================
-- PART 3 : TRIGGERS
-- ============================================================================

-- Trigger 1 : transactions are permanent (BR4)
CREATE OR REPLACE TRIGGER trg_txn_immutable
BEFORE UPDATE OR DELETE ON transactions
BEGIN
  RAISE_APPLICATION_ERROR(-20001, 'Transaction records are permanent: UPDATE/DELETE not allowed (BR4)');
END;
/

-- Trigger 2 : a debit may never take the balance below the minimum balance (BR2)
CREATE OR REPLACE TRIGGER trg_account_balance_check
BEFORE UPDATE OF balance ON account
FOR EACH ROW
BEGIN
  IF :NEW.balance < :OLD.balance AND :NEW.balance < :NEW.min_balance THEN
    RAISE_APPLICATION_ERROR(-20002, 'Balance cannot fall below the minimum balance of ' || :NEW.min_balance || ' (BR2)');
  END IF;
END;
/

-- Trigger 3 : no transaction on a FROZEN or CLOSED account (FR14)
CREATE OR REPLACE TRIGGER trg_txn_account_status
BEFORE INSERT ON transactions
FOR EACH ROW
DECLARE
  v_status account.status%TYPE;
BEGIN
  SELECT status INTO v_status FROM account WHERE account_no = :NEW.account_no;
  IF v_status IN ('FROZEN','CLOSED') THEN
    RAISE_APPLICATION_ERROR(-20004, 'Account ' || :NEW.account_no || ' is ' || v_status || ': transaction rejected (FR14)');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN NULL;   -- the foreign key reports a missing account
END;
/

-- Trigger 4 : after an EMI is paid, reduce loan outstanding and auto-close the loan (FR21, FR22, BR13)
-- The instalment contains interest; the outstanding falls by the principal part
-- (amount_paid - interest on the outstanding), i.e. the reducing-balance method.
CREATE OR REPLACE TRIGGER trg_loan_outstanding
AFTER UPDATE OF pay_status ON loan_payment
FOR EACH ROW
WHEN (OLD.pay_status = 'PENDING' AND NEW.pay_status IN ('PAID','LATE'))
DECLARE
  v_out  loan.outstanding_amt%TYPE;
  v_rate loan.interest_rate%TYPE;
  v_int  NUMBER;
  v_new  NUMBER;
BEGIN
  SELECT outstanding_amt, interest_rate INTO v_out, v_rate
  FROM loan WHERE loan_id = :NEW.loan_id FOR UPDATE;
  v_int := ROUND(v_out * v_rate / 1200, 2);
  v_new := v_out - (:NEW.amount_paid - v_int);
  IF v_new < 1 THEN            -- clears paise left over by rounding
    v_new := 0;
  END IF;
  UPDATE loan
     SET outstanding_amt = v_new,
         status = CASE WHEN v_new = 0 THEN 'CLOSED' ELSE status END
   WHERE loan_id = :NEW.loan_id;
END;
/

-- Trigger 5 : a branch manager must be a 'Manager' working in that same branch (BR14)
CREATE OR REPLACE TRIGGER trg_branch_manager_check
BEFORE INSERT OR UPDATE OF manager_id ON branch
FOR EACH ROW
WHEN (NEW.manager_id IS NOT NULL)
DECLARE
  v_branch employee.branch_id%TYPE;
  v_desig  employee.designation%TYPE;
BEGIN
  SELECT branch_id, designation INTO v_branch, v_desig FROM employee WHERE emp_id = :NEW.manager_id;
  IF v_branch <> :NEW.branch_id OR v_desig <> 'Manager' THEN
    RAISE_APPLICATION_ERROR(-20003, 'Employee ' || :NEW.manager_id || ' is not a Manager of branch ' || :NEW.branch_id || ' (BR14)');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN NULL;   -- the foreign key reports a missing employee
END;
/

-- ============================================================================
-- PART 4 : PROCEDURES (including the two CURSOR based ones)
-- ============================================================================

-- Procedure 1 : register a customer (FR1, BR11)
CREATE OR REPLACE PROCEDURE register_customer (
  p_first VARCHAR2, p_last VARCHAR2, p_dob DATE, p_gender VARCHAR2,
  p_email VARCHAR2, p_phone VARCHAR2, p_address VARCHAR2, p_city VARCHAR2,
  p_pan VARCHAR2, p_customer_id OUT NUMBER
) IS
BEGIN
  IF customer_age(p_dob) < 18 THEN
    RAISE_APPLICATION_ERROR(-20010, 'Customer must be at least 18 years old (BR11)');
  END IF;
  p_customer_id := customer_seq.NEXTVAL;
  INSERT INTO customer (customer_id, first_name, last_name, dob, gender, email, phone, address, city, pan_no)
  VALUES (p_customer_id, p_first, p_last, p_dob, p_gender, p_email, p_phone, p_address, p_city, p_pan);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Customer registered. customer_id = ' || p_customer_id || ', KYC = PENDING');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END register_customer;
/

-- Procedure 2 : verify or reject KYC (FR3)
CREATE OR REPLACE PROCEDURE verify_kyc (p_customer_id NUMBER, p_status VARCHAR2) IS
BEGIN
  IF p_status NOT IN ('VERIFIED','REJECTED') THEN
    RAISE_APPLICATION_ERROR(-20011, 'KYC status must be VERIFIED or REJECTED');
  END IF;
  UPDATE customer SET kyc_status = p_status WHERE customer_id = p_customer_id;
  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20012, 'Customer ' || p_customer_id || ' not found');
  END IF;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('KYC of customer ' || p_customer_id || ' set to ' || p_status);
END verify_kyc;
/

-- Procedure 3 : open an account with the opening deposit as first DEPOSIT transaction (FR5, BR6, BR15)
CREATE OR REPLACE PROCEDURE open_account (
  p_customer_id NUMBER, p_branch_id NUMBER, p_type VARCHAR2,
  p_deposit NUMBER, p_nominee VARCHAR2, p_account_no OUT NUMBER
) IS
  v_kyc    customer.kyc_status%TYPE;
  v_min    NUMBER;
  v_branch NUMBER;
BEGIN
  SELECT kyc_status INTO v_kyc FROM customer WHERE customer_id = p_customer_id;
  IF v_kyc <> 'VERIFIED' THEN
    RAISE_APPLICATION_ERROR(-20013, 'KYC is ' || v_kyc || '. Only VERIFIED customers can open accounts (BR6)');
  END IF;
  SELECT COUNT(*) INTO v_branch FROM branch WHERE branch_id = p_branch_id;
  IF v_branch = 0 THEN
    RAISE_APPLICATION_ERROR(-20014, 'Branch ' || p_branch_id || ' not found');
  END IF;
  v_min := CASE WHEN p_type = 'CURRENT' THEN 5000 ELSE 1000 END;
  IF p_deposit < v_min THEN
    RAISE_APPLICATION_ERROR(-20016, 'Opening deposit must be at least the minimum balance ' || v_min || ' (BR15)');
  END IF;
  p_account_no := account_seq.NEXTVAL;
  INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, nominee_name)
  VALUES (p_account_no, p_customer_id, p_branch_id, p_type, p_deposit, v_min, p_nominee);
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, channel, remarks)
  VALUES (txn_seq.NEXTVAL, p_account_no, 'DEPOSIT', p_deposit, p_deposit, 'BRANCH', 'Opening deposit');
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Account opened. account_no = ' || p_account_no || ', balance = ' || p_deposit);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20017, 'Customer ' || p_customer_id || ' not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END open_account;
/

-- Procedure 4 : deposit (FR9, FR13, FR14)
CREATE OR REPLACE PROCEDURE deposit_money (
  p_account_no NUMBER, p_amount NUMBER,
  p_channel VARCHAR2 DEFAULT 'BRANCH', p_remarks VARCHAR2 DEFAULT 'Deposit'
) IS
  v_bal    account.balance%TYPE;
  v_status account.status%TYPE;
  v_new    NUMBER;
BEGIN
  IF p_amount <= 0 THEN
    RAISE_APPLICATION_ERROR(-20018, 'Amount must be greater than zero (BR3)');
  END IF;
  SELECT balance, status INTO v_bal, v_status FROM account WHERE account_no = p_account_no FOR UPDATE;
  IF v_status IN ('FROZEN','CLOSED') THEN
    RAISE_APPLICATION_ERROR(-20019, 'Account is ' || v_status || ': deposit rejected (FR14)');
  END IF;
  v_new := v_bal + p_amount;
  UPDATE account
     SET balance = v_new, status = CASE WHEN status = 'DORMANT' THEN 'ACTIVE' ELSE status END
   WHERE account_no = p_account_no;
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, channel, remarks)
  VALUES (txn_seq.NEXTVAL, p_account_no, 'DEPOSIT', p_amount, v_new, p_channel, p_remarks);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Deposited ' || p_amount || ' into ' || p_account_no || '. New balance = ' || v_new);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20015, 'Account ' || p_account_no || ' not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END deposit_money;
/

-- Procedure 5 : withdraw without breaking the minimum balance (FR10, BR2)
CREATE OR REPLACE PROCEDURE withdraw_money (
  p_account_no NUMBER, p_amount NUMBER,
  p_channel VARCHAR2 DEFAULT 'BRANCH', p_remarks VARCHAR2 DEFAULT 'Withdrawal'
) IS
  v_bal    account.balance%TYPE;
  v_min    account.min_balance%TYPE;
  v_status account.status%TYPE;
  v_new    NUMBER;
BEGIN
  IF p_amount <= 0 THEN
    RAISE_APPLICATION_ERROR(-20018, 'Amount must be greater than zero (BR3)');
  END IF;
  SELECT balance, min_balance, status INTO v_bal, v_min, v_status
  FROM account WHERE account_no = p_account_no FOR UPDATE;
  IF v_status IN ('FROZEN','CLOSED') THEN
    RAISE_APPLICATION_ERROR(-20019, 'Account is ' || v_status || ': withdrawal rejected (FR14)');
  END IF;
  v_new := v_bal - p_amount;
  IF v_new < v_min THEN
    RAISE_APPLICATION_ERROR(-20020, 'Insufficient funds: balance would fall below minimum balance ' || v_min || ' (BR2)');
  END IF;
  UPDATE account
     SET balance = v_new, status = CASE WHEN status = 'DORMANT' THEN 'ACTIVE' ELSE status END
   WHERE account_no = p_account_no;
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, channel, remarks)
  VALUES (txn_seq.NEXTVAL, p_account_no, 'WITHDRAWAL', p_amount, v_new, p_channel, p_remarks);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Withdrew ' || p_amount || ' from ' || p_account_no || '. New balance = ' || v_new);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20015, 'Account ' || p_account_no || ' not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END withdraw_money;
/

-- Procedure 6 : transfer - debit and credit commit together or not at all (FR11, BR5)
CREATE OR REPLACE PROCEDURE transfer_funds (
  p_from_acc NUMBER, p_to_acc NUMBER, p_amount NUMBER, p_channel VARCHAR2 DEFAULT 'ONLINE'
) IS
  v_found    NUMBER := 0;
  v_from_bal NUMBER;
  v_from_min NUMBER;
  v_to_bal   NUMBER;
  v_new_from NUMBER;
  v_new_to   NUMBER;
BEGIN
  IF p_from_acc = p_to_acc THEN
    RAISE_APPLICATION_ERROR(-20021, 'Source and destination accounts must be different (BR5)');
  END IF;
  IF p_amount <= 0 THEN
    RAISE_APPLICATION_ERROR(-20018, 'Amount must be greater than zero (BR3)');
  END IF;
  -- lock both accounts in a fixed order to avoid deadlocks
  FOR r IN (SELECT account_no, balance, min_balance, status
              FROM account
             WHERE account_no IN (p_from_acc, p_to_acc)
             ORDER BY account_no
               FOR UPDATE) LOOP
    v_found := v_found + 1;
    IF r.status IN ('FROZEN','CLOSED') THEN
      RAISE_APPLICATION_ERROR(-20019, 'Account ' || r.account_no || ' is ' || r.status || ': transfer rejected (FR14)');
    END IF;
    IF r.account_no = p_from_acc THEN
      v_from_bal := r.balance;
      v_from_min := r.min_balance;
    ELSE
      v_to_bal := r.balance;
    END IF;
  END LOOP;
  IF v_found <> 2 THEN
    RAISE_APPLICATION_ERROR(-20015, 'Source or destination account not found');
  END IF;
  v_new_from := v_from_bal - p_amount;
  v_new_to   := v_to_bal + p_amount;
  IF v_new_from < v_from_min THEN
    RAISE_APPLICATION_ERROR(-20020, 'Insufficient funds: source balance would fall below minimum balance ' || v_from_min || ' (BR2)');
  END IF;
  UPDATE account SET balance = v_new_from WHERE account_no = p_from_acc;
  UPDATE account SET balance = v_new_to,
                     status  = CASE WHEN status = 'DORMANT' THEN 'ACTIVE' ELSE status END
   WHERE account_no = p_to_acc;
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, to_account_no, channel, remarks)
  VALUES (txn_seq.NEXTVAL, p_from_acc, 'TRANSFER_OUT', p_amount, v_new_from, p_to_acc, p_channel, 'Transfer to ' || p_to_acc);
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, to_account_no, channel, remarks)
  VALUES (txn_seq.NEXTVAL, p_to_acc, 'TRANSFER_IN', p_amount, v_new_to, p_from_acc, p_channel, 'Transfer from ' || p_from_acc);
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Transferred ' || p_amount || ' from ' || p_from_acc || ' to ' || p_to_acc ||
                       '. Balances now: ' || v_new_from || ' / ' || v_new_to);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END transfer_funds;
/

-- Procedure 7 : approve a loan, compute EMI and generate the EMI schedule (FR18, FR19, FR20, BR6, BR7, BR13)
CREATE OR REPLACE PROCEDURE approve_loan (
  p_loan_id NUMBER, p_emp_id NUMBER, p_start_date DATE DEFAULT NULL
) IS
  v_loan   loan%ROWTYPE;
  v_desig  employee.designation%TYPE;
  v_estat  employee.status%TYPE;
  v_kyc    customer.kyc_status%TYPE;
  v_emi    NUMBER;
  v_start  DATE;
BEGIN
  SELECT * INTO v_loan FROM loan WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_loan.status <> 'APPLIED' THEN
    RAISE_APPLICATION_ERROR(-20022, 'Loan ' || p_loan_id || ' is ' || v_loan.status || ', only APPLIED loans can be approved');
  END IF;
  SELECT designation, status INTO v_desig, v_estat FROM employee WHERE emp_id = p_emp_id;
  IF v_desig NOT IN ('Loan Officer','Manager') OR v_estat <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20023, 'Only an ACTIVE Loan Officer or Manager can approve loans (BR7)');
  END IF;
  SELECT kyc_status INTO v_kyc FROM customer WHERE customer_id = v_loan.customer_id;
  IF v_kyc <> 'VERIFIED' THEN
    RAISE_APPLICATION_ERROR(-20024, 'Customer KYC is ' || v_kyc || ': loan cannot be approved (BR6)');
  END IF;
  v_emi   := calculate_emi(v_loan.principal_amt, v_loan.interest_rate, v_loan.tenure_months);
  v_start := NVL(p_start_date, ADD_MONTHS(TRUNC(SYSDATE), 1));
  UPDATE loan
     SET approved_by     = p_emp_id,
         emi_amount      = v_emi,
         start_date      = v_start,
         outstanding_amt = principal_amt,
         status          = 'ACTIVE'
   WHERE loan_id = p_loan_id;
  FOR i IN 1 .. v_loan.tenure_months LOOP
    INSERT INTO loan_payment (payment_id, loan_id, due_date)
    VALUES (payment_seq.NEXTVAL, p_loan_id, ADD_MONTHS(v_start, i - 1));
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Loan ' || p_loan_id || ' approved. EMI = ' || v_emi || ', ' ||
                       v_loan.tenure_months || ' instalments generated from ' || TO_CHAR(v_start, 'DD-Mon-YYYY'));
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20025, 'Loan, employee or customer not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END approve_loan;
/

-- Procedure 8 : pay the earliest pending EMI of a loan (FR21, BR9, BR16, BR17)
-- Writes the EMI_PAYMENT transaction, debits the account and links LOAN_PAYMENT in ONE database transaction.
-- trg_loan_outstanding then reduces the outstanding amount / closes the loan.
CREATE OR REPLACE PROCEDURE pay_emi (
  p_loan_id NUMBER, p_account_no NUMBER, p_channel VARCHAR2 DEFAULT 'ONLINE'
) IS
  v_loan  loan%ROWTYPE;
  v_acc   account%ROWTYPE;
  v_pay   loan_payment%ROWTYPE;
  v_fee   NUMBER;
  v_total NUMBER;
  v_txn   NUMBER;
BEGIN
  SELECT * INTO v_loan FROM loan WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_loan.status <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20026, 'Loan ' || p_loan_id || ' is ' || v_loan.status || ': no EMI can be paid');
  END IF;
  SELECT * INTO v_acc FROM account WHERE account_no = p_account_no FOR UPDATE;
  IF v_acc.customer_id <> v_loan.customer_id THEN
    RAISE_APPLICATION_ERROR(-20027, 'Account does not belong to the loan holder (BR17)');
  END IF;
  IF v_acc.status IN ('FROZEN','CLOSED') THEN
    RAISE_APPLICATION_ERROR(-20019, 'Account is ' || v_acc.status || ': EMI payment rejected (FR14)');
  END IF;
  SELECT * INTO v_pay FROM loan_payment
   WHERE payment_id = (SELECT MIN(payment_id) FROM loan_payment
                        WHERE loan_id = p_loan_id AND pay_status = 'PENDING')
     FOR UPDATE;
  v_fee   := calc_late_fee(v_loan.emi_amount, v_pay.due_date);
  v_total := v_loan.emi_amount + v_fee;                      -- BR9
  IF v_acc.balance - v_total < v_acc.min_balance THEN
    RAISE_APPLICATION_ERROR(-20020, 'Insufficient funds for EMI ' || v_total || ' (BR2)');
  END IF;
  v_txn := txn_seq.NEXTVAL;
  UPDATE account SET balance = balance - v_total WHERE account_no = p_account_no;
  INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, channel, remarks)
  VALUES (v_txn, p_account_no, 'EMI_PAYMENT', v_total, v_acc.balance - v_total, p_channel,
          'EMI of loan ' || p_loan_id || ' due ' || TO_CHAR(v_pay.due_date, 'DD-Mon-YYYY'));
  UPDATE loan_payment
     SET txn_id      = v_txn,
         paid_date   = TRUNC(SYSDATE),
         amount_paid = v_loan.emi_amount,
         late_fee    = v_fee,
         pay_status  = CASE WHEN v_fee > 0 THEN 'LATE' ELSE 'PAID' END
   WHERE payment_id = v_pay.payment_id;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('EMI paid for loan ' || p_loan_id || ': instalment ' || v_loan.emi_amount ||
                       ' + late fee ' || v_fee || ' = ' || v_total || ' (txn ' || v_txn || ')');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20028, 'Loan, account or pending EMI not found');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pay_emi;
/

-- Procedure 9 (CURSOR) : mark dormant accounts with no transaction for p_days days (FR8)
CREATE OR REPLACE PROCEDURE mark_dormant_accounts (p_days NUMBER DEFAULT 180) IS
  CURSOR c_accounts IS
    SELECT a.account_no,
           NVL(MAX(t.txn_date), CAST(a.opened_on AS TIMESTAMP)) AS last_activity
      FROM account a
      LEFT JOIN transactions t ON t.account_no = a.account_no
     WHERE a.status = 'ACTIVE'
     GROUP BY a.account_no, a.opened_on;
  v_count NUMBER := 0;
BEGIN
  FOR r IN c_accounts LOOP
    IF r.last_activity < SYSTIMESTAMP - NUMTODSINTERVAL(p_days, 'DAY') THEN
      UPDATE account SET status = 'DORMANT' WHERE account_no = r.account_no;
      v_count := v_count + 1;
      DBMS_OUTPUT.PUT_LINE('Account ' || r.account_no || ' marked DORMANT (last activity ' ||
                           TO_CHAR(r.last_activity, 'DD-Mon-YYYY') || ')');
    END IF;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_count || ' account(s) marked dormant.');
END mark_dormant_accounts;
/

-- Procedure 10 (CURSOR) : add late fee to every overdue pending EMI (FR21, BR9)
CREATE OR REPLACE PROCEDURE apply_late_fees IS
  CURSOR c_overdue IS
    SELECT lp.payment_id, lp.loan_id, lp.due_date, l.emi_amount
      FROM loan_payment lp
      JOIN loan l ON l.loan_id = lp.loan_id
     WHERE lp.pay_status = 'PENDING'
       AND lp.due_date < TRUNC(SYSDATE)
       AND l.status = 'ACTIVE';
  v_fee   NUMBER;
  v_count NUMBER := 0;
BEGIN
  FOR r IN c_overdue LOOP
    v_fee := calc_late_fee(r.emi_amount, r.due_date);
    UPDATE loan_payment SET late_fee = v_fee WHERE payment_id = r.payment_id;
    v_count := v_count + 1;
    DBMS_OUTPUT.PUT_LINE('Loan ' || r.loan_id || ', EMI due ' || TO_CHAR(r.due_date, 'DD-Mon-YYYY') ||
                         ' is overdue. Late fee = ' || v_fee);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_count || ' overdue EMI(s) updated with late fee.');
END apply_late_fees;
/

-- Procedure 11 (parameterised CURSOR) : statement for a date range (FR12)
CREATE OR REPLACE PROCEDURE print_statement (p_account_no NUMBER, p_from DATE, p_to DATE) IS
  CURSOR c_stmt (cp_acc NUMBER, cp_from DATE, cp_to DATE) IS
    SELECT txn_id, txn_date, txn_type, amount, balance_after, channel
      FROM transactions
     WHERE account_no = cp_acc
       AND txn_date >= cp_from AND txn_date < cp_to + 1
     ORDER BY txn_date, txn_id;
  v_n NUMBER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('STATEMENT FOR ACCOUNT ' || p_account_no || '  ' || TO_CHAR(p_from,'DD-Mon-YYYY') || ' to ' || TO_CHAR(p_to,'DD-Mon-YYYY'));
  DBMS_OUTPUT.PUT_LINE(RPAD('TXN',6) || RPAD('DATE',22) || RPAD('TYPE',14) || LPAD('AMOUNT',12) || LPAD('BALANCE',14) || '  CHANNEL');
  FOR r IN c_stmt(p_account_no, p_from, p_to) LOOP
    v_n := v_n + 1;
    DBMS_OUTPUT.PUT_LINE(RPAD(r.txn_id,6) || RPAD(TO_CHAR(r.txn_date,'DD-Mon-YYYY HH24:MI'),22) ||
                         RPAD(r.txn_type,14) || LPAD(TO_CHAR(r.amount,'FM9999999990.00'),12) ||
                         LPAD(TO_CHAR(r.balance_after,'FM99999999990.00'),14) || '  ' || r.channel);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(v_n || ' transaction(s) listed.');
END print_statement;
/

-- Check that everything compiled (should say "no rows selected")
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

-- ============================================================================
-- PART 5 : DML - DATA POPULATION (10+ rows in every table)
-- ============================================================================

-- ---- BRANCH (manager assigned after employees exist) ----
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (1,  'Vellore Main',          'RBNK0000001', 'Vellore',    'Tamil Nadu',    '9444100001');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (2,  'Chennai Anna Nagar',    'RBNK0000002', 'Chennai',    'Tamil Nadu',    '9444100002');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (3,  'Bengaluru Indiranagar', 'RBNK0000003', 'Bengaluru',  'Karnataka',     '9444100003');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (4,  'Hyderabad Banjara Hills','RBNK0000004','Hyderabad',  'Telangana',     '9444100004');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (5,  'Mumbai Andheri',        'RBNK0000005', 'Mumbai',     'Maharashtra',   '9444100005');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (6,  'Delhi Connaught Place', 'RBNK0000006', 'New Delhi',  'Delhi',         '9444100006');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (7,  'Kolkata Salt Lake',     'RBNK0000007', 'Kolkata',    'West Bengal',   '9444100007');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (8,  'Pune Kothrud',         'RBNK0000008', 'Pune',       'Maharashtra',   '9444100008');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (9,  'Coimbatore RS Puram',   'RBNK0000009', 'Coimbatore', 'Tamil Nadu',    '9444100009');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (10, 'Katpadi',              'RBNK0000010', 'Vellore',    'Tamil Nadu',    '9444100010');

-- ---- EMPLOYEE (10 managers + 5 other staff) ----
INSERT INTO employee VALUES (101, 1,  'Ramesh Kumar',    'Manager',      'ramesh.kumar@rbank.in',    '9876500101', 95000, DATE '2015-06-01', 'ACTIVE');
INSERT INTO employee VALUES (102, 2,  'Sunita Reddy',    'Manager',      'sunita.reddy@rbank.in',    '9876500102', 92000, DATE '2016-02-15', 'ACTIVE');
INSERT INTO employee VALUES (103, 3,  'Arvind Iyer',     'Manager',      'arvind.iyer@rbank.in',     '9876500103', 98000, DATE '2014-09-10', 'ACTIVE');
INSERT INTO employee VALUES (104, 4,  'Meera Nair',      'Manager',      'meera.nair@rbank.in',      '9876500104', 90000, DATE '2017-01-20', 'ACTIVE');
INSERT INTO employee VALUES (105, 5,  'Vikram Rao',      'Manager',      'vikram.rao@rbank.in',      '9876500105', 99000, DATE '2013-11-05', 'ACTIVE');
INSERT INTO employee VALUES (106, 6,  'Anjali Sharma',   'Manager',      'anjali.sharma@rbank.in',   '9876500106', 97000, DATE '2015-08-30', 'ACTIVE');
INSERT INTO employee VALUES (107, 7,  'Pradeep Singh',   'Manager',      'pradeep.singh@rbank.in',   '9876500107', 91000, DATE '2016-12-12', 'ACTIVE');
INSERT INTO employee VALUES (108, 8,  'Kavita Das',      'Manager',      'kavita.das@rbank.in',      '9876500108', 93000, DATE '2018-03-18', 'ACTIVE');
INSERT INTO employee VALUES (109, 9,  'Sanjay Patil',    'Manager',      'sanjay.patil@rbank.in',    '9876500109', 89000, DATE '2017-07-07', 'ACTIVE');
INSERT INTO employee VALUES (110, 10, 'Lakshmi Menon',   'Manager',      'lakshmi.menon@rbank.in',   '9876500110', 94000, DATE '2016-05-25', 'ACTIVE');
INSERT INTO employee VALUES (111, 1,  'Divya Krishnan',  'Loan Officer', 'divya.krishnan@rbank.in',  '9876500111', 60000, DATE '2019-04-01', 'ACTIVE');
INSERT INTO employee VALUES (112, 2,  'Mohan Raj',       'Teller',       'mohan.raj@rbank.in',       '9876500112', 35000, DATE '2020-06-15', 'ACTIVE');
INSERT INTO employee VALUES (113, 3,  'Priya Venkat',    'Clerk',        'priya.venkat@rbank.in',    '9876500113', 32000, DATE '2021-01-11', 'ACTIVE');
INSERT INTO employee VALUES (114, 4,  'Rohit Verma',     'Loan Officer', 'rohit.verma@rbank.in',     '9876500114', 62000, DATE '2018-10-09', 'ACTIVE');
INSERT INTO employee VALUES (115, 5,  'Neha Gupta',      'Auditor',      'neha.gupta@rbank.in',      '9876500115', 70000, DATE '2019-09-23', 'ACTIVE');

-- ---- assign branch managers (trigger trg_branch_manager_check validates each) ----
UPDATE branch SET manager_id = 101 WHERE branch_id = 1;
UPDATE branch SET manager_id = 102 WHERE branch_id = 2;
UPDATE branch SET manager_id = 103 WHERE branch_id = 3;
UPDATE branch SET manager_id = 104 WHERE branch_id = 4;
UPDATE branch SET manager_id = 105 WHERE branch_id = 5;
UPDATE branch SET manager_id = 106 WHERE branch_id = 6;
UPDATE branch SET manager_id = 107 WHERE branch_id = 7;
UPDATE branch SET manager_id = 108 WHERE branch_id = 8;
UPDATE branch SET manager_id = 109 WHERE branch_id = 9;
UPDATE branch SET manager_id = 110 WHERE branch_id = 10;
COMMIT;

-- ---- CUSTOMER (1001-1010 KYC verified, 1011 pending, 1012 rejected) ----
INSERT INTO customer VALUES (1001, 'Aarav',  'Sharma',   DATE '1990-03-15', 'M', 'aarav.sharma@mail.com',  '9811000001', '12 MG Road',          'Vellore',    'ABCPS1234A', 'VERIFIED', DATE '2024-06-10');
INSERT INTO customer VALUES (1002, 'Diya',   'Patel',    DATE '1988-07-22', 'F', 'diya.patel@mail.com',    '9811000002', '45 Anna Salai',       'Chennai',    'BCDPP2345B', 'VERIFIED', DATE '2024-07-02');
INSERT INTO customer VALUES (1003, 'Rohan',  'Mehta',    DATE '1995-11-05', 'M', 'rohan.mehta@mail.com',   '9811000003', '8 Indiranagar 1st St','Bengaluru',  'CDEPM3456C', 'VERIFIED', DATE '2024-08-19');
INSERT INTO customer VALUES (1004, 'Ananya', 'Iyer',     DATE '1992-01-30', 'F', 'ananya.iyer@mail.com',   '9811000004', '21 Banjara Hills',    'Hyderabad',  'DEFPI4567D', 'VERIFIED', DATE '2024-09-05');
INSERT INTO customer VALUES (1005, 'Karthik','Raj',      DATE '1985-09-12', 'M', 'karthik.raj@mail.com',   '9811000005', '3 Andheri West',      'Mumbai',     'EFGPR5678E', 'VERIFIED', DATE '2024-10-14');
INSERT INTO customer VALUES (1006, 'Sneha',  'Kulkarni', DATE '1998-04-18', 'F', 'sneha.kulkarni@mail.com','9811000006', '77 Connaught Place',  'New Delhi',  'FGHPK6789F', 'VERIFIED', DATE '2024-11-21');
INSERT INTO customer VALUES (1007, 'Imran',  'Khan',     DATE '1991-12-02', 'M', 'imran.khan@mail.com',    '9811000007', '14 Salt Lake Sec V',  'Kolkata',    'GHIPK7890G', 'VERIFIED', DATE '2025-01-08');
INSERT INTO customer VALUES (1008, 'Pooja',  'Nair',     DATE '1993-06-25', 'F', 'pooja.nair@mail.com',    '9811000008', '5 Kothrud',           'Pune',       'HIJPN8901H', 'VERIFIED', DATE '2025-02-17');
INSERT INTO customer VALUES (1009, 'Vivek',  'Menon',    DATE '1980-02-14', 'M', 'vivek.menon@mail.com',   '9811000009', '9 RS Puram',          'Coimbatore', 'IJKPM9012I', 'VERIFIED', DATE '2024-01-15');
INSERT INTO customer VALUES (1010, 'Neelam', 'Joshi',    DATE '1987-10-09', 'F', 'neelam.joshi@mail.com',  '9811000010', '30 Katpadi Road',     'Vellore',    'JKLPJ0123J', 'VERIFIED', DATE '2025-03-03');
INSERT INTO customer VALUES (1011, 'Arjun',  'Das',      DATE '2000-08-08', 'M', 'arjun.das@mail.com',     '9811000011', '6 Park Street',       'Kolkata',    'KLMPD1234K', 'PENDING',  DATE '2026-09-20');
INSERT INTO customer VALUES (1012, 'Fatima', 'Begum',    DATE '1996-05-20', 'F', 'fatima.begum@mail.com',  '9811000012', '18 Charminar Road',   'Hyderabad',  'LMNPB2345L', 'REJECTED', DATE '2026-09-25');
COMMIT;

-- ---- ACCOUNT (balance = opening deposit; later activity goes through procedures) ----
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000001, 1001, 1,  'SAVINGS',  50000,  1000, DATE '2024-06-10', 'ACTIVE', 'Meena Sharma');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000002, 1002, 2,  'SAVINGS',  75000,  1000, DATE '2024-07-02', 'ACTIVE', 'Raj Patel');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000003, 1003, 3,  'SALARY',   30000,  1000, DATE '2024-08-19', 'ACTIVE', 'Sheela Mehta');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000004, 1004, 4,  'SAVINGS',  120000, 1000, DATE '2024-09-05', 'ACTIVE', 'Gopal Iyer');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000005, 1005, 5,  'CURRENT',  250000, 5000, DATE '2024-10-14', 'ACTIVE', 'Latha Raj');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000006, 1006, 6,  'SAVINGS',  45000,  1000, DATE '2024-11-21', 'ACTIVE', 'Anil Kulkarni');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000007, 1007, 7,  'SAVINGS',  20000,  1000, DATE '2025-01-08', 'ACTIVE', 'Shabana Khan');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000008, 1008, 8,  'SALARY',   60000,  1000, DATE '2025-02-17', 'ACTIVE', 'Suresh Nair');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000009, 1009, 9,  'SAVINGS',  15000,  1000, DATE '2024-01-15', 'ACTIVE', 'Rekha Menon');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000010, 1010, 10, 'CURRENT',  180000, 5000, DATE '2025-03-03', 'ACTIVE', 'Ramesh Joshi');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000011, 1001, 1,  'CURRENT',  100000, 5000, DATE '2025-04-12', 'ACTIVE', 'Meena Sharma');
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance, min_balance, opened_on, status, nominee_name) VALUES (500000000012, 1003, 3,  'SAVINGS',  10000,  1000, DATE '2024-02-20', 'ACTIVE', 'Sheela Mehta');

-- ---- TRANSACTIONS : opening deposit of every account (first DEPOSIT row, BR15) ----
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000001, 'DEPOSIT', 50000,  TIMESTAMP '2024-06-10 10:30:00', 50000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000002, 'DEPOSIT', 75000,  TIMESTAMP '2024-07-02 11:00:00', 75000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000003, 'DEPOSIT', 30000,  TIMESTAMP '2024-08-19 09:45:00', 30000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000004, 'DEPOSIT', 120000, TIMESTAMP '2024-09-05 14:15:00', 120000, 'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000005, 'DEPOSIT', 250000, TIMESTAMP '2024-10-14 12:00:00', 250000, 'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000006, 'DEPOSIT', 45000,  TIMESTAMP '2024-11-21 10:10:00', 45000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000007, 'DEPOSIT', 20000,  TIMESTAMP '2025-01-08 15:30:00', 20000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000008, 'DEPOSIT', 60000,  TIMESTAMP '2025-02-17 13:20:00', 60000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000009, 'DEPOSIT', 15000,  TIMESTAMP '2024-01-15 10:00:00', 15000,  'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000010, 'DEPOSIT', 180000, TIMESTAMP '2025-03-03 11:45:00', 180000, 'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000011, 'DEPOSIT', 100000, TIMESTAMP '2025-04-12 16:00:00', 100000, 'BRANCH', 'Opening deposit');
INSERT INTO transactions (txn_id, account_no, txn_type, amount, txn_date, balance_after, channel, remarks) VALUES (txn_seq.NEXTVAL, 500000000012, 'DEPOSIT', 10000,  TIMESTAMP '2024-02-20 10:20:00', 10000,  'BRANCH', 'Opening deposit');
COMMIT;

-- ---- TRANSACTIONS : day-to-day activity through the procedures (deposit, withdraw, transfer) ----
BEGIN
  deposit_money (500000000001, 10000, 'ONLINE', 'Salary credit');
  withdraw_money(500000000002, 5000,  'ATM',    'ATM cash withdrawal');
  transfer_funds(500000000004, 500000000001, 15000, 'UPI');
  deposit_money (500000000003, 5000,  'BRANCH', 'Cash deposit');
  withdraw_money(500000000005, 20000, 'BRANCH', 'Cheque withdrawal');
  transfer_funds(500000000005, 500000000010, 50000, 'ONLINE');
  deposit_money (500000000006, 8000,  'UPI',    'UPI top-up');
  withdraw_money(500000000007, 2000,  'ATM',    'ATM cash withdrawal');
  transfer_funds(500000000008, 500000000002, 10000, 'ONLINE');
  deposit_money (500000000011, 25000, 'BRANCH', 'Cash deposit');
END;
/

-- ---- CARD (12 cards: one BLOCKED, one EXPIRED) ----
INSERT INTO card VALUES ('4000123400000001', 500000000001, 'DEBIT',  'AARAV SHARMA',   DATE '2024-06-15', DATE '2029-06-30', 50000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000002', 500000000002, 'DEBIT',  'DIYA PATEL',     DATE '2024-07-10', DATE '2029-07-31', 40000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000003', 500000000003, 'DEBIT',  'ROHAN MEHTA',    DATE '2024-08-25', DATE '2029-08-31', 30000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000004', 500000000004, 'CREDIT', 'ANANYA IYER',    DATE '2024-09-12', DATE '2029-09-30', 100000, 'ACTIVE');
INSERT INTO card VALUES ('4000123400000005', 500000000005, 'DEBIT',  'KARTHIK RAJ',    DATE '2024-10-20', DATE '2029-10-31', 75000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000006', 500000000006, 'DEBIT',  'SNEHA KULKARNI', DATE '2024-11-28', DATE '2029-11-30', 50000,  'BLOCKED');
INSERT INTO card VALUES ('4000123400000007', 500000000007, 'DEBIT',  'IMRAN KHAN',     DATE '2025-01-15', DATE '2030-01-31', 25000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000008', 500000000008, 'CREDIT', 'POOJA NAIR',     DATE '2025-02-25', DATE '2030-02-28', 80000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000009', 500000000009, 'DEBIT',  'VIVEK MENON',    DATE '2019-03-01', DATE '2024-03-01', 50000,  'EXPIRED');
INSERT INTO card VALUES ('4000123400000010', 500000000010, 'DEBIT',  'NEELAM JOSHI',   DATE '2025-03-10', DATE '2030-03-31', 60000,  'ACTIVE');
INSERT INTO card VALUES ('4000123400000011', 500000000011, 'CREDIT', 'AARAV SHARMA',   DATE '2025-04-20', DATE '2030-04-30', 150000, 'ACTIVE');
INSERT INTO card VALUES ('4000123400000012', 500000000012, 'DEBIT',  'ROHAN MEHTA',    DATE '2024-02-25', DATE '2029-02-28', 20000,  'ACTIVE');
COMMIT;

-- ---- LOAN : 10 applications (status APPLIED by default) ----
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (1,  1001, 'HOME',      2500000, 8.50,  120, ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (2,  1002, 'CAR',        600000, 9.50,  60,  ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (3,  1003, 'PERSONAL',   200000, 12.00, 24,  ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (4,  1004, 'EDUCATION',  800000, 7.50,  84,  ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (5,  1005, 'HOME',      4000000, 8.75,  180, ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (6,  1006, 'PERSONAL',   100000, 14.00, 12,  ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (7,  1007, 'CAR',        450000, 10.00, 48,  ADD_MONTHS(TRUNC(SYSDATE), -3));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (8,  1008, 'PERSONAL',   150000, 13.00, 18,  TRUNC(SYSDATE) - 5);
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (9,  1009, 'EDUCATION',  500000, 8.00,  60,  ADD_MONTHS(TRUNC(SYSDATE), -1));
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months, applied_on) VALUES (10, 1010, 'HOME',      3000000, 9.00,  240, ADD_MONTHS(TRUNC(SYSDATE), -3));
COMMIT;

-- ---- LOAN approvals : procedure computes EMI and creates the EMI schedule (LOAN_PAYMENT rows) ----
-- Start date 2 months back so that the first EMIs are already due / overdue (useful for demos).
BEGIN
  approve_loan(1,  111, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(2,  111, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(3,  114, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(4,  114, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(5,  101, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(6,  111, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(7,  114, ADD_MONTHS(TRUNC(SYSDATE), -2));
  approve_loan(10, 110, ADD_MONTHS(TRUNC(SYSDATE), -2));
END;
/
-- Loan 9 is rejected by a Loan Officer; loan 8 stays APPLIED (approved later in the demo section)
UPDATE loan SET status = 'REJECTED', approved_by = 114 WHERE loan_id = 9;
COMMIT;

-- ---- First EMI of the active loans is paid (late, because it fell due 2 months ago) ----
BEGIN
  pay_emi(1,  500000000001, 'ONLINE');
  pay_emi(2,  500000000002, 'ONLINE');
  pay_emi(3,  500000000003, 'BRANCH');
  pay_emi(4,  500000000004, 'ONLINE');
  pay_emi(5,  500000000005, 'ONLINE');
  pay_emi(6,  500000000006, 'UPI');
  pay_emi(7,  500000000007, 'ONLINE');
  pay_emi(10, 500000000010, 'ONLINE');
END;
/
-- Overdue pending EMIs get their late fee through the cursor procedure
BEGIN
  apply_late_fees;
END;
/

-- ---- Row count check (every table must have at least 10 rows) ----
SELECT 'BRANCH' AS table_name, COUNT(*) AS row_count FROM branch
UNION ALL SELECT 'EMPLOYEE',     COUNT(*) FROM employee
UNION ALL SELECT 'CUSTOMER',     COUNT(*) FROM customer
UNION ALL SELECT 'ACCOUNT',      COUNT(*) FROM account
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM transactions
UNION ALL SELECT 'CARD',         COUNT(*) FROM card
UNION ALL SELECT 'LOAN',         COUNT(*) FROM loan
UNION ALL SELECT 'LOAN_PAYMENT', COUNT(*) FROM loan_payment;

-- ============================================================================
-- PART 6 : SQL QUERIES (19 queries)
-- ============================================================================

PROMPT ===== Q1  KYC verified customers (selection, ordering) =====
SELECT customer_id, first_name || ' ' || last_name AS customer_name, city, phone, kyc_status
FROM customer
WHERE kyc_status = 'VERIFIED'
ORDER BY city, customer_name;

PROMPT ===== Q2  Accounts with customer and branch (3-table JOIN) =====
SELECT a.account_no, c.first_name || ' ' || c.last_name AS customer_name, b.branch_name,
       a.account_type, a.balance, a.status
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch   b ON b.branch_id   = a.branch_id
ORDER BY a.account_no;

PROMPT ===== Q3  Branch-wise total deposits and number of accounts (FR24, LEFT JOIN + GROUP BY) =====
SELECT b.branch_name, COUNT(a.account_no) AS no_of_accounts, NVL(SUM(a.balance), 0) AS total_deposits
FROM branch b
LEFT JOIN account a ON a.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name
ORDER BY total_deposits DESC;

PROMPT ===== Q4  Top 5 customers by total balance (FR25, inline view + ROWNUM) =====
SELECT * FROM (
  SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name, SUM(a.balance) AS total_balance
  FROM customer c
  JOIN account a ON a.customer_id = c.customer_id
  GROUP BY c.customer_id, c.first_name, c.last_name
  ORDER BY total_balance DESC
) WHERE ROWNUM <= 5;

PROMPT ===== Q5  Loans with overdue EMIs (FR26) =====
SELECT l.loan_id, c.first_name || ' ' || c.last_name AS customer_name, l.loan_type,
       COUNT(*) AS overdue_emis, SUM(l.emi_amount + lp.late_fee) AS amount_due,
       MIN(lp.due_date) AS oldest_due_date
FROM loan l
JOIN loan_payment lp ON lp.loan_id = l.loan_id
JOIN customer c      ON c.customer_id = l.customer_id
WHERE lp.pay_status = 'PENDING' AND lp.due_date < TRUNC(SYSDATE)
GROUP BY l.loan_id, c.first_name, c.last_name, l.loan_type
ORDER BY oldest_due_date, l.loan_id;

PROMPT ===== Q6  Statement of account 500000000001 (FR12, FR13) =====
SELECT txn_id, txn_date, txn_type, amount, balance_after, to_account_no, channel, remarks
FROM transactions
WHERE account_no = 500000000001
ORDER BY txn_date, txn_id;

PROMPT ===== Q7  Month-wise transaction summary of two accounts (FR27, GROUP BY with CASE) =====
SELECT account_no, TO_CHAR(txn_date, 'YYYY-MM') AS txn_month, COUNT(*) AS txn_count,
       SUM(CASE WHEN txn_type IN ('DEPOSIT','TRANSFER_IN') THEN amount ELSE 0 END) AS total_credit,
       SUM(CASE WHEN txn_type IN ('WITHDRAWAL','TRANSFER_OUT','EMI_PAYMENT') THEN amount ELSE 0 END) AS total_debit
FROM transactions
WHERE account_no IN (500000000001, 500000000005)
GROUP BY account_no, TO_CHAR(txn_date, 'YYYY-MM')
ORDER BY account_no, txn_month;

PROMPT ===== Q8  Accounts holding more than the average balance (scalar subquery) =====
SELECT account_no, customer_id, account_type, balance
FROM account
WHERE balance > (SELECT AVG(balance) FROM account)
ORDER BY balance DESC;

PROMPT ===== Q9  Customers who have no loan (NOT EXISTS) =====
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name, c.city
FROM customer c
WHERE NOT EXISTS (SELECT 1 FROM loan l WHERE l.customer_id = c.customer_id)
ORDER BY c.customer_id;

PROMPT ===== Q10 Customers holding more than one account (GROUP BY ... HAVING) =====
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name,
       COUNT(a.account_no) AS no_of_accounts, SUM(a.balance) AS combined_balance
FROM customer c
JOIN account a ON a.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(a.account_no) > 1;

PROMPT ===== Q11 Branch, its manager and staff strength (self-referencing JOINs on EMPLOYEE) =====
SELECT b.branch_id, b.branch_name, m.emp_name AS manager_name, COUNT(e.emp_id) AS staff_count
FROM branch b
LEFT JOIN employee m ON m.emp_id = b.manager_id
LEFT JOIN employee e ON e.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, m.emp_name
ORDER BY b.branch_id;

PROMPT ===== Q12 Loan-type wise summary (aggregation) =====
SELECT loan_type, COUNT(*) AS no_of_loans, SUM(principal_amt) AS total_principal,
       ROUND(AVG(interest_rate), 2) AS avg_rate, SUM(NVL(outstanding_amt, 0)) AS total_outstanding
FROM loan
GROUP BY loan_type
ORDER BY total_principal DESC;

PROMPT ===== Q13 EMI collected and late fee earned per loan (JOIN + HAVING) =====
SELECT l.loan_id, l.loan_type, COUNT(lp.payment_id) AS emis_paid, SUM(lp.amount_paid) AS emi_collected,
       SUM(lp.late_fee) AS late_fee_collected, l.outstanding_amt
FROM loan l
JOIN loan_payment lp ON lp.loan_id = l.loan_id AND lp.pay_status IN ('PAID','LATE')
GROUP BY l.loan_id, l.loan_type, l.outstanding_amt
HAVING SUM(lp.amount_paid) > 0
ORDER BY l.loan_id;

PROMPT ===== Q14 Cards with holder, account and status (JOIN, date filter) =====
SELECT cd.card_no, cd.card_type, cd.holder_name, a.account_no, cd.expiry_date, cd.card_status,
       CASE WHEN cd.expiry_date < TRUNC(SYSDATE) THEN 'EXPIRED' ELSE 'VALID' END AS validity
FROM card cd
JOIN account a ON a.account_no = cd.account_no
ORDER BY cd.expiry_date;

PROMPT ===== Q15 Dormant candidates: no transaction in the last 180 days (NOT EXISTS, FR8) =====
SELECT a.account_no, a.customer_id, a.status, a.opened_on
FROM account a
WHERE a.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM transactions t
                  WHERE t.account_no = a.account_no
                    AND t.txn_date >= SYSTIMESTAMP - INTERVAL '180' DAY(3));

PROMPT ===== Q16 Transactions larger than the average of their own type (correlated subquery) =====
SELECT t.txn_id, t.account_no, t.txn_type, t.amount
FROM transactions t
WHERE t.amount > (SELECT AVG(t2.amount) FROM transactions t2 WHERE t2.txn_type = t.txn_type)
ORDER BY t.txn_type, t.amount DESC;

PROMPT ===== Q17 Highest paid employee in each branch (analytic RANK) =====
SELECT * FROM (
  SELECT b.branch_name, e.emp_name, e.designation, e.salary,
         RANK() OVER (PARTITION BY e.branch_id ORDER BY e.salary DESC) AS salary_rank
  FROM employee e
  JOIN branch b ON b.branch_id = e.branch_id
) WHERE salary_rank = 1
ORDER BY branch_name;

PROMPT ===== Q18 Account holders who have no active or closed loan (set operation MINUS) =====
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer_name
FROM customer c
WHERE c.customer_id IN (
  SELECT customer_id FROM account
  MINUS
  SELECT customer_id FROM loan WHERE status IN ('ACTIVE','CLOSED')
);

PROMPT ===== Q19 Channel-wise transaction count and value =====
SELECT channel, COUNT(*) AS txn_count, SUM(amount) AS total_amount, MAX(amount) AS largest
FROM transactions
GROUP BY channel
ORDER BY total_amount DESC;

-- ============================================================================
-- PART 7 : REAL-WORLD TRANSACTION DEMONSTRATIONS (INSERT / UPDATE / DELETE + PL/SQL)
-- Flow : user operation -> SQL/PL/SQL -> database processing -> table update -> result
-- ============================================================================

PROMPT ===== D1  INSERT : register a new customer (register_customer, customer_age) =====
DECLARE
  v_id NUMBER;
BEGIN
  register_customer('Meghna', 'Rao', DATE '1999-02-11', 'F', 'meghna.rao@mail.com', '9811000013',
                    '22 Gandhi Nagar', 'Vellore', 'MNOPR1234M', v_id);
END;
/
PROMPT -- a minor is rejected (age check, BR11)
BEGIN
  DECLARE v_id NUMBER;
  BEGIN
    register_customer('Tiny', 'Tot', ADD_MONTHS(TRUNC(SYSDATE), -12*15), 'M', 'tiny.tot@mail.com', '9811000014',
                      'Nowhere', 'Vellore', 'NOPQT1234N', v_id);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
SELECT customer_id, first_name, last_name, kyc_status, created_on FROM customer WHERE customer_id >= 1011 ORDER BY customer_id;

PROMPT ===== D2  UPDATE : KYC verification, then open an account (verify_kyc, open_account) =====
PROMPT -- customer 1011 has KYC PENDING, so account opening fails (BR6)
BEGIN
  DECLARE v_acc NUMBER;
  BEGIN
    open_account(1011, 7, 'SAVINGS', 5000, 'Mita Das', v_acc);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
BEGIN
  verify_kyc(1011, 'VERIFIED');
END;
/
PROMPT -- opening deposit below minimum balance is rejected (BR15)
BEGIN
  DECLARE v_acc NUMBER;
  BEGIN
    open_account(1011, 7, 'SAVINGS', 500, 'Mita Das', v_acc);
  END;
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
DECLARE
  v_acc NUMBER;
BEGIN
  open_account(1011, 7, 'SAVINGS', 5000, 'Mita Das', v_acc);
END;
/
SELECT a.account_no, a.customer_id, a.balance, t.txn_type, t.amount, t.balance_after, t.remarks
FROM account a JOIN transactions t ON t.account_no = a.account_no
WHERE a.customer_id = 1011;

PROMPT ===== D3  Deposit / Withdraw / Transfer with get_balance (FR9, FR10, FR11) =====
SELECT get_balance(500000000003) AS balance_before FROM dual;
BEGIN
  deposit_money(500000000003, 2500, 'ONLINE', 'Online deposit');
  withdraw_money(500000000003, 1500, 'ATM', 'ATM withdrawal');
END;
/
SELECT get_balance(500000000003) AS balance_after FROM dual;
PROMPT -- withdrawal that would break the minimum balance is rejected and rolled back (BR2)
BEGIN
  withdraw_money(500000000003, 999999, 'BRANCH', 'Too large');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- transfer: debit and credit are written together (two TRANSACTIONS rows)
BEGIN
  transfer_funds(500000000006, 500000000007, 3000, 'UPI');
END;
/
SELECT txn_id, account_no, txn_type, amount, balance_after, to_account_no
FROM transactions
WHERE account_no IN (500000000006, 500000000007) AND txn_type IN ('TRANSFER_OUT','TRANSFER_IN');
PROMPT -- failed transfer (insufficient funds) changes nothing
BEGIN
  transfer_funds(500000000007, 500000000006, 5000000, 'UPI');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
PROMPT -- transfer to the same account is rejected (BR5)
BEGIN
  transfer_funds(500000000006, 500000000006, 100, 'UPI');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/

PROMPT ===== D4  Trigger trg_txn_immutable : transactions cannot be changed or deleted (BR4) =====
UPDATE transactions SET amount = 1 WHERE txn_id = 1;
DELETE FROM transactions WHERE txn_id = 1;

PROMPT ===== D5  Trigger trg_account_balance_check : direct debit below minimum balance (BR2) =====
UPDATE account SET balance = 100 WHERE account_no = 500000000001;
PROMPT -- the CHECK constraint stops a negative balance on a new account (BR2)
INSERT INTO account (account_no, customer_id, branch_id, account_type, balance) VALUES (500000000098, 1001, 1, 'SAVINGS', -50);

PROMPT ===== D6  UPDATE : freeze an account; trigger trg_txn_account_status blocks transactions (FR7, FR14) =====
UPDATE account SET status = 'FROZEN' WHERE account_no = 500000000007;
COMMIT;
BEGIN
  deposit_money(500000000007, 1000, 'BRANCH', 'Test deposit');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, remarks)
VALUES (txn_seq.NEXTVAL, 500000000007, 'DEPOSIT', 1000, 21000, 'Direct insert on frozen account');
UPDATE account SET status = 'ACTIVE' WHERE account_no = 500000000007;
COMMIT;

PROMPT ===== D7  Trigger trg_branch_manager_check : manager must be a Manager of the same branch (BR14) =====
UPDATE branch SET manager_id = 112 WHERE branch_id = 1;
UPDATE branch SET manager_id = 102 WHERE branch_id = 1;
PROMPT -- valid change: employee 101 is a Manager of branch 1
UPDATE branch SET manager_id = 101 WHERE branch_id = 1;
COMMIT;

PROMPT ===== D8  Loan lifecycle : approve (BR7), EMI schedule, pay_emi (BR17), trigger updates outstanding =====
PROMPT -- a Teller (112) cannot approve a loan (BR7)
BEGIN
  approve_loan(8, 112);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
BEGIN
  approve_loan(8, 114);     -- Loan Officer approves, schedule starts next month
END;
/
SELECT loan_id, loan_type, principal_amt, emi_amount, start_date, outstanding_amt, status, approved_by FROM loan WHERE loan_id = 8;
SELECT payment_id, due_date, pay_status FROM loan_payment WHERE loan_id = 8 AND ROWNUM <= 3 ORDER BY payment_id;
PROMPT -- paying from somebody else's account is rejected (BR17)
BEGIN
  pay_emi(8, 500000000002, 'ONLINE');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Expected error -> ' || SQLERRM);
END;
/
BEGIN
  pay_emi(8, 500000000008, 'ONLINE');
END;
/
SELECT l.loan_id, l.outstanding_amt, l.status, lp.payment_id, lp.pay_status, lp.amount_paid, lp.late_fee, lp.txn_id
FROM loan l JOIN loan_payment lp ON lp.loan_id = l.loan_id
WHERE l.loan_id = 8 AND lp.txn_id IS NOT NULL;

PROMPT ===== D9  Automatic loan closure : small 2-month loan paid fully (trigger trg_loan_outstanding, FR22) =====
DECLARE
  v_loan NUMBER;
BEGIN
  v_loan := loan_seq.NEXTVAL;
  INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months)
  VALUES (v_loan, 1001, 'PERSONAL', 6000, 12, 2);
  approve_loan(v_loan, 111);
  pay_emi(v_loan, 500000000011, 'ONLINE');
  pay_emi(v_loan, 500000000011, 'ONLINE');
  DBMS_OUTPUT.PUT_LINE('Demo loan id = ' || v_loan);
END;
/
SELECT loan_id, principal_amt, emi_amount, outstanding_amt, status FROM loan WHERE principal_amt = 6000;

PROMPT ===== D10 Cursor procedures : late fees, dormant accounts, statement =====
BEGIN
  apply_late_fees;
  mark_dormant_accounts(180);
END;
/
SELECT account_no, status FROM account WHERE status = 'DORMANT';
PROMPT -- a deposit re-activates a dormant account
BEGIN
  deposit_money(500000000009, 2000, 'BRANCH', 'Deposit into dormant account');
END;
/
SELECT account_no, status, balance FROM account WHERE account_no = 500000000009;
BEGIN
  print_statement(500000000001, ADD_MONTHS(TRUNC(SYSDATE), -24), TRUNC(SYSDATE));
END;
/

PROMPT ===== D11 UPDATE : change contact details of a customer (FR2) =====
UPDATE customer SET phone = '9811099999', address = '99 New Street', city = 'Katpadi' WHERE customer_id = 1002;
SELECT customer_id, phone, address, city FROM customer WHERE customer_id = 1002;
PROMPT -- duplicate phone number is rejected by the UNIQUE constraint (BR10)
UPDATE customer SET phone = '9811000001' WHERE customer_id = 1002;
COMMIT;

PROMPT ===== D12 DELETE : remove a customer who never opened an account; FK protects the others =====
-- customer 1013 (Meghna Rao) was registered in D1 and has no accounts
DELETE FROM customer WHERE customer_id = 1013;
SELECT COUNT(*) AS meghna_rows_left FROM customer WHERE customer_id = 1013;
COMMIT;
PROMPT -- deleting a customer who owns accounts is blocked by the foreign key (ORA-02292)
DELETE FROM customer WHERE customer_id = 1001;
PROMPT -- deleting an employee who approved loans is blocked as well
DELETE FROM employee WHERE emp_id = 111;
ROLLBACK;
COMMIT;

PROMPT ===== D13 Constraint checks : CHECK / UNIQUE / NOT NULL violations =====
INSERT INTO loan (loan_id, customer_id, loan_type, principal_amt, interest_rate, tenure_months) VALUES (999, 1001, 'HOME', 100000, 45, 12);
INSERT INTO transactions (txn_id, account_no, txn_type, amount, balance_after, to_account_no) VALUES (txn_seq.NEXTVAL, 500000000001, 'TRANSFER_OUT', 100, 1000, NULL);
INSERT INTO account (account_no, customer_id, branch_id, account_type) VALUES (500000000099, 1001, 1, 'FIXED');
INSERT INTO branch (branch_id, branch_name, ifsc_code, city, state, phone) VALUES (11, 'Dup IFSC', 'RBNK0000001', 'Vellore', 'Tamil Nadu', '9444100011');

-- ============================================================================
-- PART 8 : FINAL VERIFICATION
-- ============================================================================
PROMPT ===== Compilation errors (expect none) =====
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

PROMPT ===== Triggers, procedures and functions created =====
SELECT trigger_name, table_name, triggering_event, status FROM user_triggers ORDER BY trigger_name;
SELECT object_name, object_type, status FROM user_objects WHERE object_type IN ('PROCEDURE','FUNCTION') ORDER BY object_type, object_name;

PROMPT ===== Audit : every account balance equals its latest balance_after =====
SELECT a.account_no, a.balance AS account_balance,
       (SELECT t.balance_after FROM transactions t
         WHERE t.txn_id = (SELECT MAX(t2.txn_id) FROM transactions t2 WHERE t2.account_no = a.account_no)) AS last_balance_after
FROM account a
ORDER BY a.account_no;

SPOOL OFF
-- ============================== END OF REVIEW II SCRIPT ==============================
