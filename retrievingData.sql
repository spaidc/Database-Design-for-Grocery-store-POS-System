USE sapo
--====================================
--QUERY 1 – Shift cash discrepancy audit
WITH ShiftRevenue AS (
    SELECT
        o.workshiftId,
        SUM(p.totalAmt) AS cashRevenue
    FROM [Orders] o
    JOIN [Payment] p ON p.orderId = o.id
    WHERE LOWER(o.status) = 'completed'
      AND (LOWER(p.paymentMethod) = 'cash' OR p.paymentMethod = N'Tiền mặt')
    GROUP BY o.workshiftId
)
SELECT
    ws.id AS workshiftId,
    e.[name] AS employeeName,
    ws.startTime,
    ws.endTime,
    ws.startingCash,
    ws.endingCash,
    ISNULL(sr.cashRevenue, 0) AS cashRevenue,
    (ISNULL(ws.startingCash, 0) + ISNULL(sr.cashRevenue, 0)) AS expectedEndingCash,
    (ISNULL(ws.endingCash, 0) - (ISNULL(ws.startingCash, 0) + ISNULL(sr.cashRevenue, 0))) AS discrepancy
FROM [WorkShifts] ws
JOIN [Employee] e ON e.id = ws.empId
LEFT JOIN ShiftRevenue sr ON sr.workshiftId = ws.id
WHERE ws.endingCash IS NOT NULL
  AND ws.startingCash IS NOT NULL
  AND (ISNULL(ws.endingCash, 0) <> (ISNULL(ws.startingCash, 0) + ISNULL(sr.cashRevenue, 0)))
ORDER BY ABS(ISNULL(ws.endingCash, 0) - (ISNULL(ws.startingCash, 0) + ISNULL(sr.cashRevenue, 0))) DESC;

--====================================
--QUERY 2 – Completed orders not fully paid
WITH PayAgg AS (
    SELECT orderId, SUM(totalAmt) AS paidAmt, COUNT(*) AS paymentCount
    FROM [Payment]
    GROUP BY orderId
)
SELECT
    o.id AS orderId,
    o.code,
    o.[date],
    o.finalAmt,
    ISNULL(pa.paidAmt, 0) AS paidAmt,
    (o.finalAmt - ISNULL(pa.paidAmt, 0)) AS unpaidDiff,
    ISNULL(pa.paymentCount, 0) AS paymentCount
FROM [Orders] o
LEFT JOIN PayAgg pa ON pa.orderId = o.id
WHERE LOWER(o.status) = 'completed'
  AND ISNULL(pa.paidAmt, 0) <> o.finalAmt
ORDER BY ABS(o.finalAmt - ISNULL(pa.paidAmt, 0)) DESC;

====================================
--QUERY 3 – Dead stock detection
WITH SoldLast30 AS (
    SELECT od.variantId, SUM(od.quantity) AS qtySold30
    FROM [OrderDetail] od
    JOIN [Orders] o ON o.id = od.[orderID]
    WHERE LOWER(o.status) = 'completed'
      AND o.[date] >= DATEADD(DAY, -30, GETDATE())
    GROUP BY od.variantId
)
SELECT
    pv.id,
    p.[name],
    pv.variantName,
    pv.sku,
    pv.stockQuantity
FROM [ProductsVariants] pv
JOIN [Products] p ON p.id = pv.productID
LEFT JOIN SoldLast30 s ON s.variantId = pv.id
WHERE pv.stockQuantity > 100
  AND ISNULL(s.qtySold30, 0) = 0
ORDER BY pv.stockQuantity DESC;

====================================
--QUERY 4 – Profit by category
WITH LineFacts AS (
    SELECT
        c.id AS categoryId,
        c.[name] AS categoryName,
        od.subtotal AS revenueLine,
        od.quantity * pv.entryPrice AS costLine
    FROM [OrderDetail] od
    JOIN [Orders] o ON o.id = od.[orderID]
    JOIN [ProductsVariants] pv ON pv.id = od.variantId
    JOIN [Products] p ON p.id = pv.productID
    JOIN [Category] c ON c.id = p.categoryId
    WHERE LOWER(o.status) = 'completed'
)
SELECT
    categoryName,
    SUM(revenueLine) AS totalRevenue,
    SUM(costLine) AS totalCost,
    SUM(revenueLine) - SUM(costLine) AS totalProfit
FROM LineFacts
GROUP BY categoryName
ORDER BY totalProfit DESC;

====================================
--QUERY 5 – Top 3 customers per group
WITH CustAgg AS (
    SELECT
        cg.[name] AS groupName,
        cu.id AS customerId,
        cu.[name] AS customerName,
        SUM(o.finalAmt) AS netRevenue
    FROM [Orders] o
    JOIN [Customer] cu ON cu.id = o.customerId
    JOIN [CustomerGroup] cg ON cg.id = cu.groupId
    WHERE LOWER(o.status) = 'completed'
    GROUP BY cg.[name], cu.id, cu.[name]
),
Ranked AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY groupName ORDER BY netRevenue DESC) AS rnk
    FROM CustAgg
)
SELECT *
FROM Ranked
WHERE rnk <= 3
ORDER BY groupName, rnk;

====================================
--QUERY 6 – Market basket (frequent pairs)
WITH PairCounts AS (
    SELECT
        od1.variantId AS variantA,
        od2.variantId AS variantB,
        COUNT(*) AS pairCount
    FROM [OrderDetail] od1
    JOIN [OrderDetail] od2
      ON od1.[orderID] = od2.[orderID]
     AND od1.variantId < od2.variantId
    JOIN [Orders] o ON o.id = od1.[orderID]
    WHERE LOWER(o.status) = 'completed'
    GROUP BY od1.variantId, od2.variantId
)
SELECT TOP 20 *
FROM PairCounts
ORDER BY pairCount DESC;

====================================
--QUERY 7 – Recursive unit conversion to base units
WITH Chain AS (
    SELECT id AS variantId, id AS currentId, baseVariantID, CAST(1 AS bigint) AS factor
    FROM [ProductsVariants]
    UNION ALL
    SELECT c.variantId, pv.id, pv.baseVariantID, c.factor * pv.conversionRate
    FROM Chain c
    JOIN [ProductsVariants] pv ON pv.id = c.baseVariantID
    WHERE c.baseVariantID IS NOT NULL
),
Resolved AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY variantId ORDER BY currentId) AS rn
    FROM Chain
)
SELECT *
FROM Resolved
WHERE rn = 1;

====================================
--QUERY 8 – Supplier debt exposure + latest purchase order
WITH LatestPO AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY supplierId ORDER BY [date] DESC) AS rn
    FROM [PurchaseOrders]
)
SELECT
    s.id,
    s.[name],
    s.debtBalance,
    l.code,
    l.[date]
FROM [Suppliers] s
LEFT JOIN LatestPO l ON l.supplierId = s.id AND l.rn = 1
ORDER BY s.debtBalance DESC;

====================================
--QUERY 9 – Inventory turnover (slow movers)
WITH Sales60 AS (
    SELECT od.variantId, SUM(od.quantity) AS qtySold60
    FROM [OrderDetail] od
    JOIN [Orders] o ON o.id = od.[orderID]
    WHERE LOWER(o.status) = 'completed'
      AND o.[date] >= DATEADD(DAY, -60, GETDATE())
    GROUP BY od.variantId
)
SELECT
    pv.id,
    pv.variantName,
    pv.stockQuantity,
    ISNULL(s.qtySold60, 0) AS qtySold60
FROM [ProductsVariants] pv
LEFT JOIN Sales60 s ON s.variantId = pv.id
ORDER BY qtySold60 ASC;

====================================
--QUERY 10 – Daily report reconciliation
WITH LiveDaily AS (
    SELECT CAST([date] AS date) AS reportDate,
           COUNT(*) AS totalOrders,
           SUM(finalAmt) AS totalRevenue
    FROM [Orders]
    WHERE LOWER(status) = 'completed'
    GROUP BY CAST([date] AS date)
)
SELECT
    ld.reportDate,
    ld.totalOrders AS liveOrders,
    ds.totalOrder AS storedOrders,
    ld.totalRevenue AS liveRevenue,
    ds.totalRevenue AS storedRevenue
FROM LiveDaily ld
LEFT JOIN [DailySaleReport] ds ON ds.[date] = ld.reportDate
ORDER BY ld.reportDate DESC;
