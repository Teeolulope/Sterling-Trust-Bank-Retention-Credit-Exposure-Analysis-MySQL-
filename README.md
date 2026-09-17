# Sterling Trust Bank — Retention & Credit Exposure Analysis

**MySQL | SQL | Customer Retention | Churn Analysis | Credit Risk**

SQL analysis of a synthetic retail banking dataset covering customer records, loan performance, transaction activity, and churn.

The project moves from **raw, inconsistent data to a cleaned analysis layer**, then investigates four key business areas:

* Customer churn and reasons for leaving
* Declining customer transaction activity
* Credit exposure by loan-to-income risk tier
* Customers registered but showing no transaction activity

> **Data Note:** This project uses a synthetic dataset created for portfolio purposes. Names, incomes, transactions, and other values are randomly generated and do not represent any real bank or customer. Because the data is synthetic, relationships between variables may largely reflect random variation. Findings are presented as **observations from the dataset**, not real-world banking conclusions.

---

## Business Questions

The retention committee wants to understand customer disengagement and potential credit exposure.

This analysis answers:

1. **How significant is customer churn, and why are customers leaving?**
2. **Which customers show a significant decline in transaction activity compared with their own history?**
3. **Where is loan exposure concentrated by loan-to-income risk tier?**
4. **How many registered customers have never recorded a transaction?**

---

## Dataset

| Table          |   Rows | Description                           |
| -------------- | -----: | ------------------------------------- |
| `Customers`    |    510 | Customer demographics and income      |
| `Loans`        |    568 | Customer loan records and loan status |
| `Transactions` | 18,740 | Customer transaction activity         |
| `ChurnLog`     |    500 | Customer churn records and reasons    |

**Transaction period:** 2025-01-01 → 2026-08-24
**Loan issue period:** 2023-01-05 → 2025-06-19

---

## Data Quality & Cleaning

Several data-quality issues were identified and addressed before analysis:

* **Region inconsistencies:** 13 different spellings/capitalisation patterns were standardised into 5 regions.
* **Loan status inconsistencies:** 10 variants such as `Default`, `defaulted`, `DEFAULT`, and `Paid-Off` were standardised into 3 statuses.
* **Duplicate records:** 7 duplicate customer rows and 5 duplicate loan rows were removed using `SELECT DISTINCT`.
* **Missing churn reasons:** 35 of the 110 churned customers had no recorded reason. These were labelled `Unknown` rather than excluded from the analysis.
* **Customer coverage:** Customers without a corresponding record in `ChurnLog` were checked explicitly rather than assumed to be churn-free.

The raw tables remain unchanged as an audit trail. Cleaned versions are stored as:

```text
Cleaned_Customers
Cleaned_Loans
```

## Analysis Method

### **1. Churn Analysis**

Two derived fields were created in `ChurnLog`:

* **Churn_status** — identifies customers as Churned or Not Churned based on whether a `ChurnDate` exists.
* **Churn_risk** — identifies customers showing significant transaction decline based on their historical activity.

### **2. Customer Activity Decline**

Customer activity was divided into 60-day periods based on each customer's latest transaction.

For each customer:

* **Period 0** → Most recent 60 days
* **Period 1** → 60–119 days before latest activity
* **Period 2** → 120–179 days before latest activity
* **Period 3** → 180–239 days before latest activity

Transactions were counted within each period.

The analysis then compares:

**Recent 60-Day Activity**

versus

**Historical Average Activity**

A customer is flagged as **At Risk** when their recent activity falls below **50% of their historical average**.

<img width="1563" height="659" alt="Customer Activity Decline" src="https://github.com/user-attachments/assets/876f169b-485b-4f64-8022-c80d31070a91" />

<img width="1569" height="423" alt="Customer Activity Analysis" src="https://github.com/user-attachments/assets/a8a59dfa-66ad-4e56-94df-b8db51ec44c7" />

**Method used:**

* Recent 60-day activity is compared with the historical average.
* Customers with activity below 50% of their historical average are flagged **At Risk**.

**Important:** This is a retrospective engagement signal, not a predictive churn model. Because the window is anchored to each customer's latest transaction, it measures whether activity declined before their most recent activity rather than predicting whether they will churn in the future.

### **3. Loan-to-Income Risk Tier**

A `Loan_Income_Ratio` was calculated using:

**Loan Income Ratio = (Loan Amount / Income) × 100**

Loans were then classified into three tiers:

| Tier        | Loan-to-Income Ratio |
| ----------- | -------------------: |
| Low Risk    |                ≤ 28% |
| Medium Risk |      > 28% and < 50% |
| High Risk   |                ≥ 50% |

<img width="1548" height="268" alt="Loan Income Risk Tier" src="https://github.com/user-attachments/assets/c4d7c284-f26a-4ec4-92fa-77d09f59dda1" />

**Methodological Note:** The 28% and 50% thresholds are used here as portfolio segmentation rules. The calculation compares loan principal with annual income, so it is a leverage proxy, not a true debt-service or affordability ratio.

### **4. Loan Exposure & Customer Churn**

Loan and churn data were joined to determine how much active loan principal is held by customers flagged as **At Risk**.

<img width="1511" height="104" alt="Loan Exposure and Customer Churn" src="https://github.com/user-attachments/assets/764a7c5b-28cc-4b4d-baf0-7b755f4003d1" />

This connects customer engagement risk with outstanding credit exposure, allowing the analysis to identify where active loan balances are held by customers showing declining activity.

## Key Findings

* **Churn rate:** 22% churned vs 78% retained.
* **Top churn reasons:** Unknown (31.8%).
* **Churn by region / tenure / age:** Lagos / 10+ / 45–59 Years.
* **Activity decline vs actual churn:** Customers flagged **At Risk** churned at 29.2% (7 of 24) vs 21.6% for **Not At Risk** (103 of 476) — roughly 1.35× higher. The direction is right, but the At Risk group is small (24 of 500), so this is a real but modest signal, not a strong predictor.
* **Active loan exposure among At Risk customers:** ₦331,168 across 5 active loans, vs ₦12,053,324 held by Not At Risk customers. At Risk customers hold about 2.7% of total active principal.

## Key Business Takeaways

The analysis is designed to move beyond simply describing the data.

Examples of decisions supported by the analysis include:

* Identifying customer segments requiring retention attention
* Understanding the main recorded reasons behind customer exits
* Identifying customers whose transaction activity has declined substantially
* Monitoring active loan exposure associated with customers showing declining engagement
* Evaluating whether the loan-to-income segmentation actually differentiates default behaviour in the dataset
* Identifying registered customers who have never become transactionally active

## Project Structure

```text
Sterling-Trust-Bank/
│
├── Sterling.sql
│   └── Data cleaning, transformation and analysis queries
│
└── docs/
    └── findings.md
        └── Detailed findings and recommendations
```

## How to Run

* Create a MySQL database containing the four raw tables:

  * `Customers`
  * `Loans`
  * `Transactions`
  * `ChurnLog`
* Open `Sterling.sql` in MySQL Workbench.
* Run the script from top to bottom.
* Review the query outputs and record the final results in:

  * `docs/findings.md`

**Note:** The script is not currently idempotent. Running it multiple times without resetting the tables may cause errors when adding derived columns such as `Churn_status`, `Churn_risk`, `Loan_Income_Ratio`, and `Tier`.

## Limitations

* The customer activity flag is retrospective, not a forward-looking churn prediction.
* Loan-to-income ratio uses loan principal ÷ annual income, rather than monthly repayment obligations.
* The risk thresholds are segmentation rules and should not be interpreted as formal lending policy.
* The dataset is synthetic, so observed relationships may reflect random variation rather than genuine banking behaviour.
* The SQL script requires the database to be reset before a clean re-run.

## Tools Used

* MySQL Workbench
* CTEs
* Joins
* Aggregations
* CASE statements
* Date functions
* Data cleaning and transformation
* Customer churn analysis
* Credit exposure analysis
