--==========================================
--Adding data and Data transformation for silver.crm_cust_info from bronze.crm_cust_info
--===========================================

------------------------------------------------------------------------
--Check For Nulls or Duplicates in Primary Key
--Expectation: No Result 
------------------------------------------------------------------------
SELECT 
cst_id, 
COUNT(*) 
FROM bronze.crm_cust_info 
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL

SELECT 
*
FROM (
	SELECT 
	*, 
	ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
	FROM bronze.crm_cust_info
	WHERE cst_id IS NOT NULL
)t WHERE flag_last = 1 

--------------------------------------------
--Check for Unwanted Spaces
--Expectation: No Result
---------------------------------------------
SELECT 
cst_gndr 
FROM bronze.crm_cust_info
WHERE cst_gndr != TRIM(cst_gndr)

SELECT 
cst_id, 
cst_key, 
TRIM(cst_firstname) AS cst_firstname,
TRIM(cst_lastname) AS cst_lastname,
cst_marital_status,
cst_gndr,
cst_create_date
FROM (
	SELECT 
	*, 
	ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
	FROM bronze.crm_cust_info
	WHERE cst_id IS NOT NULL
)t WHERE flag_last = 1 

------------------------------------------
--Data Standardization & Consistency
-------------------------------------------
SELECT DISTINCT cst_gndr
FROM bronze.crm_cust_info

--------------------
--Overall
--------------------
PRINT '>> Truncating Table: silver.crm_cust_info';
TRUNCATE TABLE silver.crm_cust_info;
PRINT '>> Inserting Data Into: silver.crm_cust_info';
INSERT INTO silver.crm_cust_info (
	cst_id,
	cst_key,
	cst_firstname,
	cst_lastname,
	cst_marital_status,
	cst_gndr,
	cst_create_date)
SELECT 
cst_id, 
cst_key, 
TRIM(cst_firstname) AS cst_firstname,
TRIM(cst_lastname) AS cst_lastname,
CASE WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
     WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
	 ELSE 'n/a'
END cst_marital_status,
CASE WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
     WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
	 ELSE 'n/a'
END cst_gndr,
cst_create_date
FROM (
	SELECT 
	*, 
	ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
	FROM bronze.crm_cust_info
	WHERE cst_id IS NOT NULL
)t WHERE flag_last = 1;

SELECT * FROM silver.crm_cust_info

--==========================================
--Adding data and Data transformation for silver.crm_prd_info from bronze.crm_prd_info
--===========================================

SELECT * FROM bronze.crm_prd_info

----------------------------------------------
--Check for Nulls
----------------------------------------------
SELECT 
prd_id,
COUNT(*)
FROM bronze.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL

SELECT 
*, 
REPLACE(SUBSTRING(prd_key, 1,5), '-', '_') AS cat_id,
SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key
FROM bronze.crm_prd_info

--WHERE SUBSTRING(prd_key, 7, LEN(prd_key)) NOT IN 
--(SELECT sls_prd_key FROM bronze.crm_sales_details)

--WHERE REPLACE(SUBSTRING(prd_key, 1,5), '-', '_') NOT IN
--(SELECT DISTINCT id FROM bronze.erp_px_cat_g1v2)

----------------------------------------------------------
--Check for unwanted space
----------------------------------------------------------
SELECT prd_nm 
FROM bronze.crm_prd_info
WHERE prd_nm != TRIM(prd_nm)

-----------------------------------------------------------
--Check for NULLs or Negative Numbers
-----------------------------------------------------------
SELECT prd_cost
FROM bronze.crm_prd_info
WHERE prd_cost < 0 OR prd_cost IS NULL

----------------------------------------------------------
--Data Standardization & Consistency
----------------------------------------------------------
SELECT DISTINCT prd_line FROM bronze.crm_prd_info

----------------------------------------------------------
--Check for Invalid Date Orders
----------------------------------------------------------
SELECT *
FROM bronze.crm_prd_info
WHERE prd_end_dt < prd_start_dt

SELECT 
prd_id,
prd_key,
prd_nm,
prd_start_dt,
prd_end_dt,
LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS prd_end_dt_test
FROM bronze.crm_prd_info
WHERE prd_key IN ('AC-HE-HL-U509-R', 'AC-HE-HL-U509')

----------------------
--Overall
-----------------------
PRINT '>> Truncating Table: silver.crm_prd_info';
TRUNCATE TABLE silver.crm_prd_info;
PRINT '>> Inserting Data Into: silver.crm_prd_info';
INSERT INTO silver.crm_prd_info (
	prd_id,
	cat_id,
	prd_key,
	prd_nm,
	prd_cost,
	prd_line,
	prd_start_dt,
	prd_end_dt
)
SELECT 
prd_id, 
REPLACE(SUBSTRING(prd_key, 1,5), '-', '_') AS cat_id,  --Extract Category ID
SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,        --Extract Product Key
prd_nm,
ISNULL(prd_cost, 0) AS prd_cost,
CASE UPPER(TRIM(prd_line))
	WHEN 'M' THEN 'Mountain'
	WHEN 'R' THEN 'Road'
	WHEN 'S' THEN 'Other Sales'
	WHEN 'T' THEN 'Touring'
	ELSE 'n/a'
END AS prd_line,
CAST(prd_start_dt AS DATE) AS prd_start_dt,
CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS DATE) AS prd_end_dt
FROM bronze.crm_prd_info;

--==========================================
--Adding data and Data transformation for silver.crm_sales_details from bronze.crm_sales_details
--===========================================

----------------------------------------------------------
--Check for Invalid Dates
----------------------------------------------------------
SELECT 
NULLIF(sls_order_dt, 0) sls_order_dt
FROM bronze.crm_sales_details
WHERE sls_order_dt <=0 
OR LEN(sls_order_dt) !=8 
OR sls_order_dt > 20500101 
OR sls_order_dt < 19900101

SELECT 
* 
FROM bronze.crm_sales_details
WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt

------------------------------------------------------------
--Check Data Consistency: Between Salesm Quantity and Price
-- >> Sales = Quantity * Price
-- >> Values must not be NULL, zero or negative
------------------------------------------------------------
SELECT DISTINCT
sls_sales AS old_sls_sales,
sls_quantity,
sls_price AS old_sls_price,
CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
		THEN sls_quantity * ABS(sls_price)
	ELSE sls_sales
END AS sls_sales,
CASE WHEN sls_price IS NULL OR sls_price <=0 
		THEN sls_sales/NULLIF(sls_quantity,0)
	ELSE sls_price
END AS sls_price
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

------------------------
--Overall
------------------------
PRINT '>> Truncating Table: silver.crm_sales_details';
TRUNCATE TABLE silver.crm_sales_details;
PRINT '>> Inserting Data Into: silver.crm_sales_details';
INSERT INTO silver.crm_sales_details (
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	sls_order_dt,
	sls_ship_dt,
	sls_due_dt,
	sls_sales,
	sls_quantity,
	sls_price
)
SELECT 
sls_ord_num,
sls_prd_key,
sls_cust_id,
CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
	ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
END AS sls_order_dt,
CASE WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
	ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
END AS sls_ship_dt,
CASE WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
	ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
END AS sls_due_dt,
CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
		THEN sls_quantity * ABS(sls_price)
	ELSE sls_sales
END AS sls_sales,
sls_quantity,
CASE WHEN sls_price IS NULL OR sls_price <=0 
		THEN sls_sales/NULLIF(sls_quantity,0)
	ELSE sls_price
END AS sls_price 
FROM bronze.crm_sales_details;
--WHERE sls_ord_num != TRIM(sls_ord_num)
--WHERE sls_prd_key NOT IN (SELECT prd_key FROM silver.crm_prd_info)
--WHERE sls_cust_id NOT IN (SELECT cst_id FROM silver.crm_cust_info)

--==========================================
--Adding data and Data transformation for silver.erp_cust_az12 from bronze.erp_cust_az12
--===========================================

---------------------------------------------
--Identify Out-Of-Range Dates
---------------------------------------------
SELECT 
bdate
FROM bronze.erp_cust_az12
WHERE bdate < '1924-01-01' OR bdate > GETDATE()

---------------------------------------------
--Data Standarization & Consistency
---------------------------------------------
SELECT DISTINCT gen
FROM bronze.erp_cust_az12

---------------------
--Overall
---------------------
PRINT '>> Truncating Table: silver.erp_cust_az12';
TRUNCATE TABLE silver.erp_cust_az12;
PRINT '>> Inserting Data Into: silver.erp_cust_az12';
INSERT INTO silver.erp_cust_az12 (
	cid,
	bdate,
	gen
)
SELECT 
CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END AS cid,
CASE WHEN bdate > GETDATE() THEN NULL 
	ELSE bdate
END AS bdate,
CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
	 WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
	 ELSE 'n/a'
END AS gen
FROM bronze.erp_cust_az12;
--WHERE CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
--	ELSE cid
--END NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)

--==========================================
--Adding data and Data transformation for silver.erp_loc_a101 from bronze.erp_loc_a101
--===========================================

-----------------------------------------------------------------
--Data Standarization & Consistency
-----------------------------------------------------------------
SELECT DISTINCT cntry 
FROM bronze.erp_loc_a101
ORDER BY cntry

---------------------
--Overall
----------------------
PRINT '>> Truncating Table: silver.erp_loc_a101';
TRUNCATE TABLE silver.erp_loc_a101;
PRINT '>> Inserting Data Into: silver.erp_loc_a101';
INSERT INTO silver.erp_loc_a101 (
	cid,
	cntry
)
SELECT 
REPLACE(cid, '-', '') AS cid, 
CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
	 WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
	 WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
	 ELSE TRIM(cntry)
END AS cntry
FROM bronze.erp_loc_a101;
--WHERE REPLACE(cid, '-', '') NOT IN (SELECT cst_key FROM silver.crm_cust_info)

--==========================================
--Adding data and Data transformation for silver.erp_px_cat_g1v2 from bronze.erp_px_cat_g1v2
--===========================================

---------------------------------------------------
--Check for Unwanted Spaces
---------------------------------------------------
SELECT * FROM bronze.erp_px_cat_g1v2
WHERE cat != TRIM(cat) OR subcat != TRIM(subcat) OR maintenance != TRIM(maintenance)

---------------------------------------------------
--Data Standarization & Consistency
---------------------------------------------------
SELECT DISTINCT 
cat 
FROM 
bronze.erp_px_cat_g1v2

SELECT DISTINCT 
subcat 
FROM 
bronze.erp_px_cat_g1v2

SELECT DISTINCT 
maintenance 
FROM 
bronze.erp_px_cat_g1v2

-------------------
Overall
-------------------
PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
TRUNCATE TABLE silver.erp_px_cat_g1v2;
PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
INSERT INTO silver.erp_px_cat_g1v2 (
	id,
	cat,
	subcat,
	maintenance
)
SELECT 
id, 
cat, 
subcat, 
maintenance 
FROM bronze.erp_px_cat_g1v2;