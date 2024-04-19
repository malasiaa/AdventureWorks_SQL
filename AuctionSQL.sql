CREATE SCHEMA Auction

--Table_Creation------------------------------------------------------------------------------

CREATE TABLE Auction.AuctionProducts ( 
ProductID INT PRIMARY KEY, 
ProductName NVARCHAR(50) NOT NULL,
InitialBidPrice DECIMAL(10,2) NOT NULL,
AuctionStartDate DATETIME NOT NULL, 
AuctionEndDate DATETIME NOT NULL,
InAuction Bit NOT NULL DEFAULT 1,
Sold Bit NOT NULL DEFAULT 0);

CREATE TABLE Auction.AuctionBids ( 
BidID INT IDENTITY(1,1) PRIMARY KEY, 
ProductID INT NOT NULL, 
CustomerID INT NOT NULL,
BidAmount DECIMAL(10,2) NOT NULL, 
BidTimestamp DATETIME NOT NULL, 
FOREIGN KEY (ProductID) REFERENCES Auction.AuctionProducts (ProductID) );

CREATE TABLE Auction.ThresholdConfig (
ProductID INT NOT NULL PRIMARY KEY,
BidIncrementAmount DECIMAL(10,2) NOT NULL DEFAULT 0.05,
MaxBidAmount MONEY NOT NULL,
InitialBidPrice DECIMAL(10,2) NOT NULL);


----TresholdConfig_Table_updates-----
CREATE TABLE Auction.ThresholdConfig (
  ProductID INT NOT NULL PRIMARY KEY,
  BidIncrementAmount DECIMAL(10,2) NOT NULL DEFAULT 0.05,
  MaxBidAmount MONEY NOT NULL,
  InitialBidPrice DECIMAL(10,2) NOT NULL);

INSERT INTO Auction.ThresholdConfig (ProductID, MaxBidAmount, InitialBidPrice)
SELECT 
  ProductID,
  ListPrice,
  CASE WHEN MakeFlag = 0 THEN 0.75 * ListPrice ELSE 0.5 * ListPrice END
FROM Production.Product;

 
--PROCEDURE_1------------------------------------------------------------------------------

CREATE PROCEDURE Auction.uspAddProductToAuction
@ProductID INT,
@AuctionEndDate DATETIME = NULL, 
@InitialBidPrice MONEY = NULL 
AS 
BEGIN 
    SET NOCOUNT ON; 
    -- Check if product is currently commercialized 
    IF EXISTS (SELECT 1 FROM Production.Product WHERE ProductID = @ProductID AND SellEndDate IS NULL AND DiscontinuedDate IS NULL) 
    BEGIN 
        -- Check if product is not already in an auction 
        IF NOT EXISTS (SELECT 1 FROM Auction.AuctionProducts WHERE ProductID = @ProductID) 
        BEGIN 
            -- Set default expiration date to one week from now 
            IF @AuctionEndDate IS NULL SET @AuctionEndDate = DATEADD(WEEK, 1, GETDATE()); 
            -- Set initial bid price based on listed price and product type 
            DECLARE @MinInitialBidPrice MONEY = (SELECT InitialBidPrice FROM Auction.ThresholdConfig WHERE ProductID = @ProductID); 
			
			-- If @initialbidprice is null
			IF @InitialBidPrice IS NULL 
            BEGIN 
                 SET @InitialBidPrice = @MinInitialBidPrice
            END;

			-- If @initialbidprice is not null the max should be the less than the listprice, otherwize it will not be in the auction
			DECLARE @MaxBidAmount MONEY; 
			SELECT @MaxBidAmount = MaxBidAmount 
			FROM Auction.ThresholdConfig
			WHERE ProductID = @ProductID; 

			IF @InitialBidPrice <=  @MaxBidAmount AND @InitialBidPrice >= @MinInitialBidPrice
			BEGIN
				-- Insert new auction product 
				INSERT INTO Auction.AuctionProducts (ProductID, ProductName, InitialBidPrice, AuctionStartDate, AuctionEndDate) 
				SELECT p.ProductID, p.Name, @InitialBidPrice, GETDATE(), @AuctionEndDate 
				FROM Production.Product p 
				WHERE p.ProductID = @ProductID; 
			END
			DECLARE @MaxErrorMessage NVARCHAR(100) = CONCAT('InitialBidPrice should be below the maximum bid limit (', CAST(@MaxBidAmount AS NVARCHAR), ').');
			IF @InitialBidPrice > @MaxBidAmount 
			BEGIN
				RAISERROR(@MaxErrorMessage, 16, 1)
			END
			DECLARE @MinErrorMessage NVARCHAR(100) = CONCAT('InitialBidPrice should be above the minimum bid limit (', CAST(@MinInitialBidPrice AS NVARCHAR), ').');
			IF @InitialBidPrice < @MinInitialBidPrice
			BEGIN
				RAISERROR(@MinErrorMessage, 16, 1)
			END
        END 
        ELSE 
        BEGIN 
            RAISERROR('Product is already in an active auction.', 16, 1); 
        END 

    END 
    ELSE 
    BEGIN 
        RAISERROR('Product is not currently commercialized.', 16, 1); 
    END 
END 


--PROCEDURE 2------------------------------------------------------------------------------


CREATE PROCEDURE Auction.uspTryBidProduct 
    @ProductID INT, 
	@CustomerID INT, 
    @BidAmount MONEY = NULL 
AS 
BEGIN 
    SET NOCOUNT ON; 
    -- Check if the product is currently in an auction 
    IF EXISTS (SELECT 1 FROM Auction.AuctionProducts WHERE ProductID = @ProductID AND AuctionEndDate > GETDATE()) 
    BEGIN 

		-- Get the initial bid price for the product 
        DECLARE @InitialBidPrice MONEY; 
        SELECT @InitialBidPrice = InitialBidPrice 
		FROM Auction.AuctionProducts
		WHERE ProductID = @ProductID; 

        -- Get the current highest bid 
        DECLARE @CurrentHighestBid MONEY; 
		SELECT TOP 1 @CurrentHighestBid = BidAmount 
        FROM Auction.AuctionBids 
        WHERE ProductID = @ProductID 
        ORDER BY BidAmount DESC;
		
		IF @CurrentHighestBid IS NULL
		BEGIN
			SET @CurrentHighestBid = @InitialBidPrice
		END;		
        
        -- Get the bid increment amount from the threshold configuration table 
        DECLARE @BidIncrementAmount MONEY; 
        SELECT @BidIncrementAmount = BidIncrementAmount 
		FROM Auction.ThresholdConfig
		WHERE ProductID = @ProductID;
        
		 -- Get the maximum bid amount 
		DECLARE @MaxBidAmount MONEY; 
		SELECT @MaxBidAmount = MaxBidAmount 
		FROM Auction.ThresholdConfig
		WHERE ProductID = @ProductID;  

		-- Calculate the new bid amount 
        DECLARE @ErrorMessage1 NVARCHAR(100) = CONCAT('New bid amount should be higher than ', CAST(@CurrentHighestBid AS NVARCHAR), '.');
		DECLARE @ErrorMessage2 NVARCHAR(100) = CONCAT('New bid amount should be higher than ', CAST(@InitialBidPrice AS NVARCHAR), '.');
		DECLARE @NewBidAmount MONEY;
        IF @BidAmount IS NOT NULL 
        BEGIN
			IF @BidAmount >= @CurrentHighestBid 
			BEGIN
				SET @NewBidAmount = @BidAmount;
			END			
			IF @BidAmount <= @CurrentHighestBid AND @CurrentHighestBid > @InitialBidPrice
			BEGIN
				RAISERROR(@ErrorMessage1, 16, 1) 
		
			END
			IF @BidAmount < @InitialBidPrice AND @CurrentHighestBid <= @InitialBidPrice
			BEGIN
				RAISERROR(@ErrorMessage2, 16, 1)
			END
			END
        ELSE 
        BEGIN 
            -- Bid amount was not specified, calculate based on threshold amount 
            SET @NewBidAmount = CASE 
				WHEN @CurrentHighestBid = @InitialBidPrice THEN @InitialBidPrice
                WHEN @CurrentHighestBid + @BidIncrementAmount > @MaxBidAmount THEN @MaxBidAmount
				ELSE @CurrentHighestBid + @BidIncrementAmount
            END; 
        END; 
        
        -- Check if the new bid amount is within the maximum bid amount 
        IF @NewBidAmount <= @MaxBidAmount
        BEGIN 
            -- Insert the new bid 
            INSERT INTO Auction.AuctionBids (ProductID, BidAmount, CustomerID, BidTimestamp) 
            SELECT @ProductID, @NewBidAmount, @CustomerID, GETDATE(); 
        END;
        IF @NewBidAmount > @MaxBidAmount
        BEGIN 
            -- New bid amount is higher than maximum allowed 
            DECLARE @ErrorMessage NVARCHAR(100) = CONCAT('New bid amount should be less than ', CAST(@MaxBidAmount AS NVARCHAR), ' allowed');
			RAISERROR(@ErrorMessage, 16, 1)
        END
		IF @NewBidAmount = @MaxBidAmount
		BEGIN
		    UPDATE Auction.AuctionProducts
			SET AuctionEndDate = GETDATE(), InAuction = 0, Sold = 1
           	WHERE ProductID = @ProductID
			PRINT 'The product is yours! It will be delivered soon :)'
		END;
    END
    ELSE 
	BEGIN 
        -- Product is not currently in an auction 
        RAISERROR('Product is not currently in an auction.', 16, 1); 
	END; 
END; 

--PROCEDURE 3------------------------------------------------------------------------------

CREATE PROCEDURE Auction.uspRemoveProductFromAuction 
    @ProductID INT 
AS 
BEGIN 
    IF EXISTS (SELECT 1 FROM Auction.AuctionProducts WHERE ProductID = @ProductID AND AuctionEndDate > GETDATE()) 
    BEGIN 
        -- Update the Auction.AuctionProducts table to mark the product as not auctioned 
        UPDATE Auction.AuctionProducts SET InAuction = 0,  AuctionEndDate = GETDATE() WHERE ProductID = @ProductID; 
        PRINT 'Product has been removed from auction.'; 
    END 
    ELSE 
    BEGIN 
        PRINT 'Product is not currently in auction or auction has already ended.'; 
    END 
END 

--PROCEDURE 4------------------------------------------------------------------------------

CREATE PROCEDURE Auction.uspListBidsOffersHistory 
    @CustomerID int, 
    @StartTime datetime, 
    @EndTime datetime, 
    @Active bit = 1
AS 
BEGIN 
    SET NOCOUNT ON; 
    IF @Active = 1 
    BEGIN 
        -- Get bid history for currently auctioned products 
        SELECT bp.BidID, bp.ProductID, bp.BidAmount, bp. BidTimestamp, ap.ProductName, ap.AuctionStartDate, ap.AuctionEndDate, ap.InAuction , ap.Sold
        FROM Auction.AuctionBids bp 
        INNER JOIN Auction.AuctionProducts ap ON bp.ProductID = ap.ProductID 
        WHERE bp.CustomerID = @CustomerID 
        AND ap. AuctionEndDate >= GETDATE() 
        AND bp. BidTimestamp BETWEEN @StartTime AND @EndTime 
        ORDER BY bp. BidTimestamp DESC; 
    END 
    ELSE 
    BEGIN 
        -- Get all bid history (including products no longer auctioned or purchased) 
        SELECT bp.BidID, bp.ProductID, bp. BidAmount, bp. BidTimestamp, ap.ProductName, ap.AuctionStartDate, ap.AuctionEndDate, ap.InAuction, ap.Sold
        FROM Auction.AuctionBids bp 
        INNER JOIN Auction.AuctionProducts ap ON bp.ProductID = ap.ProductID 
        WHERE bp.CustomerID = @CustomerID 
        AND bp. BidTimestamp BETWEEN @StartTime AND @EndTime 
        ORDER BY bp. BidTimestamp DESC; 
    END 
END


--PROCEDURE 5------------------------------------------------------------------------------


CREATE PROCEDURE Auction.uspUpdateProductAuctionStatus 
AS 
BEGIN 
    -- Update auction status for all auctioned products 
    UPDATE Auction.AuctionProducts 
    SET InAuction = 0 
    WHERE AuctionEndDate <= GETDATE(); 
END 