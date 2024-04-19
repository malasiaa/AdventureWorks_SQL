
----Cities to recommend---------------------------------------

CREATE TABLE CustomerSales (
  CustomerID INT PRIMARY KEY not NULL,
  PersonType VARCHAR(20) not null,
  TotalOrderAmount DECIMAL(18,2) not NULL,
  City NVARCHAR(max) not NULL,
  CountryRegionCode VARCHAR(5) not NULL
);

----Updating Table---------------------------------------

INSERT INTO CustomerSales (CustomerID, PersonType, TotalOrderAmount, City, CountryRegionCode)
SELECT 
  c.CustomerID, 
  CASE WHEN pc.PersonType = 'SC' THEN 'Store' ELSE 'Individual' END AS PersonType,
  SUM(soh.TotalDue) AS TotalOrderAmount,
  a.City,
  sp.CountryRegionCode
FROM 
  Sales.Customer c
  JOIN Sales.SalesOrderHeader soh ON c.CustomerID = soh.CustomerID
  JOIN Person.Person pc ON c.PersonID = pc.BusinessEntityID
  JOIN Person.Address a ON soh.BillToAddressID = a.AddressID
  JOIN Person.StateProvince sp ON a.StateProvinceID = sp.StateProvinceID
GROUP BY 
  c.CustomerID, pc.PersonType, a.City, sp.CountryRegionCode;

----Cities to recommend---------------------------------------

CREATE VIEW CustomerSalesVIEW
AS
SELECT TOP 2 City, SUM(TotalOrderAmount) AS TotalAmount, PersonType, CountryRegionCode
FROM CustomerSales
WHERE PersonType = 'Individual'and CountryRegionCode = 'us'
GROUP BY City, CountryRegionCode, PersonType
ORDER BY TotalAmount DESC

EXCEPT

SELECT TOP 30 City, TotalOrderAmount AS TotalAmount, PersonType, CountryRegionCode
FROM CustomerSales
WHERE PersonType = 'Store'and CountryRegionCode = 'us'
GROUP BY City, TotalOrderAmount, CountryRegionCode, PersonType
ORDER BY TotalOrderAmount DESC

EXCEPT

SELECT TOP 30 City, SUM(TotalOrderAmount) AS TotalAmount, PersonType, CountryRegionCode
FROM CustomerSales
WHERE PersonType = 'Store'and CountryRegionCode = 'us'
GROUP BY City, TotalOrderAmount, CountryRegionCode, PersonType
ORDER BY TotalAmount DESC


SELECT *
FROM CustomerSalesVIEW


SELECT COUNT(CustomerID)
FROM CustomerSales
WHERE PersonType = 'Individual' AND CountryRegionCode = 'us' AND city = 'Burbank'
ORDER BY SUM (TotalOrderAmount) DESC

SELECT COUNT(CustomerID)
FROM CustomerSales
WHERE PersonType = 'Individual' AND CountryRegionCode = 'us' AND city = 'Bellflower'
ORDER BY SUM (TotalOrderAmount) DESC


