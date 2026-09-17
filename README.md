Sterling Trust Bank — Retention & Credit Exposure Analysis (MySQL)

SQL analysis of a retail banking dataset covering customer records, loan performance, transaction activity and churn. The work moves from raw, dirty tables to a cleaned layer, then answers four business questions: how bad is churn, which customers show declining activity, where is credit risk concentrated, and how much loan exposure sits with customers who look like they're on their way out.

Data note: this is a synthetic dataset used for portfolio purposes. Names, incomes and transactions are randomly generated and do not represent any real institution or customer. Because the values are random, relationships between variables are mostly noise — findings below are reported as what the data shows, not as banking insight.

The brief

Sterling Trust Bank's retention committee has customers leaving but no view of who is disengaging, and no sense of whether the loan book is concentrated in over-leveraged borrowers. Four raw tables were handed over. The questions:

How bad is churn, and what do leavers say their reason was?
Which customers show a sharp drop in activity relative to their own history?
Where is credit exposure concentrated by loan-to-income tier?
How many registered customers have never transacted at all?
Dataset
Table	Rows (raw)	Notes
Customers	510	7 exact duplicate rows; NULLs in Income, Age, Gender
Loans	568	5 exact duplicate rows; NULLs in LoanStatus, CustomerID
Transactions	18,740	No duplicates. Dates 2025-01-01 → 2026-08-24
ChurnLog	500	110 churned. Reason populated for 75 of them

Loan issue dates run 2023-01-05 → 2025-06-19.

Data quality issues found
Region had 13 spellings for 5 cities (Lagos, lagos, LAGOS, PH, Port-Harcourt, Port Harcourt, Abuja, ABUJA, Abuja FCT, …) → standardised to 5.
LoanStatus had 10 variants for 3 states (Default, defaulted, DEFAULT, Paid-Off, paid off, PAID OFF, …) plus NULLs → standardised to 3.
Duplicates: 7 customer rows and 5 loan rows were exact duplicates, removed with SELECT DISTINCT into Cleaned_Customers / Cleaned_Loans.
Churn reasons: 35 of the 110 churned customers have no reason recorded. Labelled Unknown rather than dropped, so the reason breakdown sums to 100%.
Coverage gap: some customers in Cleaned_Customers have no row in ChurnLog at all, checked explicitly rather than assumed.
Method
1. Cleaning

Duplicates removed into Cleaned_Customers / Cleaned_Loans. Region and loan-status casing/spelling standardised on the cleaned tables only — the raw customers and loans tables are left untouched as an audit trail. Missing churn reasons labelled Unknown rather than dropped, so percentages stay interpretable.

2. Churn and engagement decline

churnlog gets two derived columns:

Churn_status — Churned / Not churned, from whether ChurnDate is set.
Churn_risk — At Risk / Not At Risk, from a 60-day transaction-decay window (below).
3. Credit risk tier

cleaned_loans gets Loan_Income_Ratio = (LoanAmount / Income) * 100, tiered:

Tier	Ratio
Low Risk	≤ 28%
Medium Risk	28–50%
High Risk	≥ 50%

The 28% threshold is the conventional housing-expense rule of thumb and 50% the total-debt ceiling, applied here to loan principal against annual income rather than monthly repayment — a leverage proxy, not a true debt-service ratio.

The 60-day decay window, in detail
sql
WITH maximum AS (
    SELECT customers.CustomerID, MAX(TransactionDate) AS latest_activity
    FROM customers
    LEFT JOIN transactions ON customers.CustomerID = transactions.CustomerID
    GROUP BY customers.CustomerID
),
period_counts AS (
    SELECT maximum.CustomerID,
           FLOOR(DATEDIFF(maximum.latest_activity, transactions.TransactionDate) / 60) AS period_number,
           COUNT(transactions.TransactionID) AS transaction_count
    FROM maximum
    JOIN transactions ON maximum.CustomerID = transactions.CustomerID
    GROUP BY maximum.CustomerID, period_number
)
-- recent_60_days vs historical_average per customer, flagged At Risk
-- when recent activity falls below half the historical average.

Read this carefully: the window is anchored to each customer's own most recent transaction, not to a fixed calendar date. So this measures whether a customer was winding down before they stopped, not whether they are likely to leave next month — a retrospective decline signal, not a forward-looking prediction. Query 5 in the analysis section cross-tabs the flag against actual churn to check whether it separates anything.

Credit tier, in detail
sql
update cleaned_loans set Tier = case
    when Loan_Income_Ratio <= 28 then "Low Risk"
    when Loan_Income_Ratio < 50  then "Medium Risk"
    when Loan_Income_Ratio >= 50 then "High Risk"
end where Loan_Income_Ratio is not null;
Repo layout
Sterling.sql        -- full script: cleaning, then analysis, in order
docs/
  findings.md        -- results and recommendations, filled from query output
How to run

Run Sterling.sql top to bottom in MySQL Workbench against a database containing the four raw tables. Not idempotent — the ALTER TABLE steps (adding Churn_status, Churn_risk, Loan_Income_Ratio, Tier) will error if run a second time without first dropping those columns. Re-run from a fresh copy of the raw tables, or drop the added columns before re-running.

Findings

(fill in from your own query output — see docs/findings.md)

Churn rate: __% churned, __% retained
Top reasons for leaving: __
Churn by region / tenure / age: biggest spread was __
Does the decline flag predict churn? __
Default rate by risk tier: __ — does the tier actually separate defaults, or is it roughly flat across tiers?
Exposure: __ in active loan principal held by customers flagged At Risk
Known limitations
The engagement flag is retrospective, not predictive (see above).
Loan-to-income uses principal against annual income, not monthly debt service.
Script is not re-runnable without resetting the raw tables first.
Dataset is synthetic; cross-segment differences are largely sampling noise rather than real signal — reported as observed, not as banking insight.
