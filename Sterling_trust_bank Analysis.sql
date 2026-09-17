-- 					DATA CLEANING
-- 1 Counting the number of rows in different tables
select count(*) from loans;
select count(*) from customers;
select count(*) from transactions;
select count(*) from churnlog;

-- 2 Identifying Duplicate in the raw table
select * from customers where CustomerID in (select CustomerID from customers group by CustomerID having count(*) > 1)
order by CustomerID desc;
select * from loans where LoanID in (select LoanID from loans group by LoanID having count(*) > 1)
order by LoanID desc;
select * from transactions where TransactionID in (select TransactionID from transactions group by TransactionID having count(*) > 1)
order by TransactionID desc;

-- 3 Build the cleaned layer (duplicates dropped)
create table Cleaned_Customers as select distinct * from customers;
create table Cleaned_loans as select distinct * from loans;

-- Confirm the duplicates are gone
select count(*) as Row_count, count(distinct CustomerID) as Unique_Custom_ID from cleaned_customers;
select count(*) as Row_count, count(distinct LoanID) as Unique_Loan_ID from cleaned_loans;


-- 4 Count Missing Values
select SUM(LoanStatus IS NULL) AS null_loan_status, SUM(CustomerID IS NULL) AS null_customer_id
FROM Cleaned_Loans;
select sum(Income is null) as Null_Income, 
sum(Age is null) as Null_Age, sum(Gender is null) as Null_Gender
from cleaned_customers;

-- 5 Standardise categorical values
-- Inspect the mess first
select distinct(LoanStatus) from cleaned_loans;
select distinct(Region) from cleaned_customers;

-- Region: 13 variants -> 5 cities
update cleaned_customers set Region = "Abuja" where lower(Region) = "abuja";
update cleaned_customers set Region = "Ibadan" where lower(Region) = "ibadan";
update cleaned_customers set Region = "Kano" where lower(Region) = "kano";
update cleaned_customers set Region = "Lagos" where lower(Region) = "lagos";

-- LoanStatus: 10 variants -> 3 states
update cleaned_loans set LoanStatus = "Defaulted" where (LoanStatus) = "Default";
update cleaned_loans set LoanStatus = "Active" where lower(LoanStatus) = "active";
update cleaned_loans set LoanStatus = "Defaulted" where lower(LoanStatus) = "defaulted";
update cleaned_loans set LoanStatus = "Paid off" where LoanStatus = "Paid-off";
update cleaned_loans set LoanStatus = "Paid off" where lower(LoanStatus) = "paid off";
update cleaned_customers set Region = "Abuja" where Region = "Abuja FCT";
update cleaned_customers set Region = "Port Harcourt" where Region = "Port-Harcourt";
update cleaned_customers set Region = "Port Harcourt" where Region = "PH";

-- Verify
select distinct(LoanStatus) from cleaned_loans;
select distinct(Region) from cleaned_customers;

-- 6. Label missing churn reasons instead of dropping them
Update churnlog set Reason = "Unknown" where Reason is null;

-- 7 Identifying customers that registered but didn't make any transaction
select distinct count(customers.CustomerID) as Count from customers left join transactions on transactions.CustomerID = customers.CustomerID
where transactions.CustomerID  is null;

-- 8 Customers with no churn record at all
select cleaned_customers.CustomerID from cleaned_customers left join churnlog 
on cleaned_customers.CustomerID = churnlog.CustomerID where churnlog.CustomerID is null;

-- 							ANALYSIS

-- 1 Creating a churn risk from customers
select * from churnlog;
alter table churnlog add column Churn_status varchar(20);
update churnlog set Churn_status = case when ChurnDate is null then "Not churned" else "Churned" end;
select round(sum(case when Churn_status = "Churned" then 1 else 0 end)/count(*) * 100, 2) As Churned_rate, 
round(sum(case when Churn_status != "Churned" then 1 else 0 end)/count(*) *100, 2) As Retention_rate
from churnlog;
alter table churnlog add column Churn_risk varchar(50);
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
    GROUP BY maximum.CustomerID, FLOOR(DATEDIFF(maximum.latest_activity, transactions.TransactionDate) / 60)
),
customer_activity AS (
    SELECT CustomerID,
           MAX(CASE WHEN period_number = 0 THEN transaction_count ELSE 0 END) AS recent_60_days,
           AVG(CASE WHEN period_number > 0 THEN transaction_count END) AS historical_average
    FROM period_counts
    GROUP BY CustomerID
)
UPDATE churnlog
JOIN customer_activity ON churnlog.CustomerID = customer_activity.CustomerID
SET churnlog.Churn_risk = CASE
    WHEN customer_activity.recent_60_days < customer_activity.historical_average * 0.5 THEN 'At Risk'
    ELSE 'Not At Risk'
END;

--  2 Churn and retention rate
select count(*) as Total_Customer, round(sum(Churn_status = "Churned")/count(*) * 100, 1) as Churned_Rate, 
round(sum(Churn_status = "Not Churned")/count(*) * 100, 1) as Retention_Rate from churnlog;

-- 3 Stated reasons for leaving (Unknown kept in, so this sums to 100%)
select distinct(Reason) from churnlog;
select Reason, count(*) as count from churnlog where ChurnDate is not null group by Reason;
select Reason, round(count(*)/(select count(*) from churnlog where Churn_status = "Churned") * 100, 1) as Reason_Percent from churnlog 
where ChurnDate is not null group by Reason ;

-- 4 Churn by region, tenure band and age band
-- By Region
select Region, count(*)as Count, round(sum(Churn_status = "Churned") / count(*) * 100, 1) as Rate
from cleaned_customers left join churnlog on cleaned_customers.CustomerID = churnlog.CustomerID
group by Region order by Rate desc;

-- By Tenure
select case when TenureYears <= 2 then "0-2 Years"
when TenureYears <= 5 then "3-5 Years"
when TenureYears <= 9 then "6-9 Years"
else "10+ Years" end as Tenure_Tier,  Count(*) as Count, 
round(sum(Churn_status = "Churned")/count(*) * 100, 1) as Rate from cleaned_customers
left join churnlog on cleaned_customers.CustomerID = churnlog.CustomerID
group by Tenure_Tier order by Rate desc;

-- By Age Band
select case when Age is null then "Umknown"
when Age < 30 then "Under Age"
when Age < 45 then "30-44 Years"
when Age < 60 then "45-59 Years"
else "60+ Years" end as Age_Band,
count(*) as Count, round(sum(Churn_status = "Churned") / count(*) * 100, 1) as Rate
from cleaned_customers left join churnlog on cleaned_customers.CustomerID = churnlog.CustomerID
group by Age_Band order by Rate desc;

--  5 Does the decline flag line up with actual churn?
select Churn_risk, count(*) as Count, sum(Churn_status = "Churned") as Total_Count, 
round(sum(Churn_status= "Churned")/count(*) * 100, 1) as Rate from churnlog group by Churn_risk;

-- 6 Identifying Customers at Loan risk 
select * from cleaned_loans;
alter table cleaned_loans add Column Loan_Income_Ratio decimal(10, 2);
update cleaned_loans join cleaned_customers on cleaned_loans.CustomerID = cleaned_customers.CustomerID
set cleaned_loans.Loan_Income_Ratio = (LoanAmount/Income) * 100;
alter table cleaned_loans add Column Tier varchar(50);
update cleaned_loans set Tier = case when Loan_Income_Ratio <= 28 then "Low Risk" when Loan_Income_Ratio <50 then "Medium Risk"
when Loan_Income_Ratio >= 50 then "High Risk" end where Loan_Income_Ratio is not null;

-- 7 Default rate by risk tier — does the tier actually separate defaults?
select Tier, count(*) as Count, sum(LoanStatus = "Defaulted") as Defaulted, 
round(sum(LoanStatus = "Defaulted")/count(*) * 100, 1) as Default_Rate
from cleaned_loans group by Tier order by Default_Rate desc;

--  8 Was risk priced in? Average rate by outcome
SELECT LoanStatus,
       COUNT(*) AS loans,
       ROUND(AVG(InterestRate), 2) AS avg_interest_rate,
       ROUND(AVG(Loan_Income_Ratio), 1) AS avg_loan_income_ratio
FROM cleaned_loans
WHERE LoanStatus IS NOT NULL
GROUP BY LoanStatus;

-- Default by Region
select Region, count(*) as Count, sum(LoanStatus = "Defaulted") as Defaultrd, 
round(sum(LoanStatus = "Defaulted") / count(*) * 100, 1) as Dafault_Rate 
from cleaned_customers left join cleaned_loans on cleaned_customers.CustomerID = cleaned_loans.CustomerID
group by Region order by Dafault_Rate desc;
