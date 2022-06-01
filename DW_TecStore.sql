USE master
GO

DROP DATABASE IF EXISTS DW_TecStore
GO

CREATE DATABASE DW_TecStore
GO

USE DW_TecStore
GO

/*--------------------------------------------------------------------------------------------------*/

CREATE TABLE DateDimension
(
	DateID DATE,
	Year INT,
	Month INT,
	Day INT,
	DayOfWeek VARCHAR(20),
	CalendarMonth VARCHAR(20),
	HolidayIndicator VARCHAR(20),
	WeekendIndicator VARCHAR(20)
	PRIMARY KEY (DateID)
)
GO

CREATE TABLE ProductDimension
(
	ProductKey NVARCHAR(100),
	idProducto INT,
	GTIN NVARCHAR(100),
	Nombre VARCHAR(200),
	Talla VARCHAR(20),
	Color VARCHAR(20),
	Division VARCHAR(20),
	Grupo VARCHAR(20)
	PRIMARY KEY (ProductKey)
)
GO

CREATE TABLE ClientDimension
(
	IDCLIENTE INT,
	Genero INT,
	BirthDate VARCHAR(100),
	Dominio VARCHAR(100),
	ClasificacionCliente VARCHAR(100)
	PRIMARY KEY (IDCLIENTE)
)
GO

CREATE TABLE AddressDimension
(
	AddressKey INT IDENTITY(1,1),
	Estado VARCHAR(100),
	Ciudad VARCHAR(100),
	CP VARCHAR(20)
	PRIMARY KEY (AddressKey)
)
GO

CREATE TABLE SalesFact
(
	id INT IDENTITY(1,1),
	ProductKey NVARCHAR(100),
	DateID DATE,
	AddressKey INT,
	IDCLIENTE INT,
	id_Order INT,
	Precio INT,
	Cantidad INT,
	Subtotal MONEY
	PRIMARY KEY (id),
	FOREIGN KEY (ProductKey) REFERENCES ProductDimension(ProductKey),
	FOREIGN KEY (DateID) REFERENCES DateDimension(DateID),
	FOREIGN KEY (AddressKey) REFERENCES AddressDimension(AddressKey),
	FOREIGN KEY (IDCLIENTE) REFERENCES ClientDimension(IDCLIENTE),
)
GO

USE TecStore
GO


-- CLIENT DIMENSION
INSERT INTO [DW_TecStore].[dbo].[ClientDimension]
SELECT DISTINCT(IDCLIENTE), MIN(genero) AS Genero, MAX(birthdate) AS BirthDate, Dominio, ClasificacionCliente  --As define nombre como columna
FROM detallePedido
GROUP BY IDCLIENTE, Dominio, ClasificacionCliente --Sirve para hacer funciones agregadas, min, max , average, suma, count, agrupas por variables que no tiene dichas funciones agregadas.
ORDER BY IDCLIENTE  --Order by trae los datos y los organiza de determinada manera 
GO

-- PRODUCT DIMENSION
INSERT INTO [DW_TecStore].[dbo].[ProductDimension]
	SELECT DISTINCT(CONCAT('G' ,CONVERT(numeric, GTIN), '-', [Id Producto])) AS ProductKey,
		[Id Producto], CONCAT('G' ,CONVERT(numeric, GTIN)) AS GTIN, Nombre, Talla, Color, División, Grupo 
	FROM Productos
	GO

-- Producto Nulo
INSERT INTO [DW_TecStore].[dbo].[ProductDimension] VALUES ('G-', NULL, 'G', NULL, NULL, NULL, NULL, NULL)
GO

-- DATE DIMENSION
INSERT INTO [DW_TecStore].[dbo].[DateDimension]
SELECT DISTINCT(CAST(fecha AS date)) AS DateID, YEAR(fecha) AS Year, MONTH(fecha) AS Month, DAY(fecha) AS Day,
	DATENAME(WEEKDAY, fecha) AS DayOfTheWeek, DATENAME(MONTH, fecha) AS CalendarMonth, 0 AS HolidayIndicator,
	CHOOSE(DATEPART(WEEKDAY, fecha), 'Weekend', 'Weekday', 'Weekday', 'Weekday', 'Weekday', 'Weekday', 'Weekend') AS WeekendIndicator
FROM detallePedido
WHERE fecha IS NOT NULL
ORDER BY DateID
GO

-- ADDRESS DIMENSION
INSERT INTO [DW_TecStore].[dbo].[AddressDimension]
SELECT DISTINCT ISNULL(estado, '-') AS Estado, ISNULL(ciudad, '-') AS Ciudad, ISNULL(CONVERT(nvarchar, postcode), '-') AS Postcode
FROM detallePedido
GROUP BY estado, ciudad, postcode    --Agrupación de todos los únicos sin que me de ningún repetido. Al momento de empatar en otras operaciones no enviar varios empates 
GO

/*--------------------------------------------------------------------------------------------------*/

--WITH se utiliza para crear tablas temporales 

-- Insertando los ProductKeys sin Correspondencia a ProductDimension con demás campos en NULL
WITH SalesFactTemp1(ProductKey, IdProducto, GTIN) AS
(
	SELECT DISTINCT CONCAT(dP.GTIN, '-', dP.IdProducto) AS ProductKey, dP.IdProducto, dP.GTIN
	FROM detallePedido dP
	JOIN [DW_TecStore].[dbo].[AddressDimension] AD 
		ON ISNULL(dP.estado, '-') = AD.Estado AND ISNULL(dP.ciudad, '-') = AD.ciudad AND ISNULL(CONVERT(nvarchar, dP.postcode), '-') = AD.CP
	WHERE dP.IdProducto IS NOT NULL
)
INSERT INTO [DW_TecStore].[dbo].[ProductDimension]
SELECT DISTINCT SFT.ProductKey, SFT.IdProducto, SFT.GTIN, NULL AS Nombre, NULL AS Talla, NULL AS Color, NULL AS Division, NULL AS Grupo
FROM SalesFactTemp1 SFT
LEFT JOIN [DW_TecStore].[dbo].[ProductDimension] PD ON SFT.ProductKey = PD.ProductKey
WHERE PD.ProductKey IS NULL  --SOLICITA DE TABLAS DONDE NO HAYA UN EMPATE.
GO

/*--------------------------------------------------------------------------------------------------*/

-- Haciendo la inserción de datos a SalesFacts
WITH SalesFactTemp2(ProductKey, DateID, AddressKey, IDCLIENTE, id_order, Precio, Cantidad, Subtotal) AS
(
	SELECT DISTINCT CONCAT(dP.GTIN, '-', dP.IdProducto) AS ProductKey, CONVERT(date, fecha) AS DateID, 
		AD.AddressKey, IDCLIENTE, id_order, Precio, Cantidad, (Precio * Cantidad) AS Subtotal
	FROM detallePedido dP
	JOIN [DW_TecStore].[dbo].[AddressDimension] AD 
		ON ISNULL(dP.estado, '-') = AD.Estado AND ISNULL(dP.ciudad, '-') = AD.ciudad AND ISNULL(CONVERT(nvarchar, dP.postcode), '-') = AD.CP
)
INSERT INTO [DW_TecStore].[dbo].[SalesFact]
SELECT SFT.ProductKey, SFT.DateID, SFT.AddressKey, SFT.IDCLIENTE, SFT.id_order, SFT.Precio, SFT.Cantidad,
	SFT.Subtotal
FROM SalesFactTemp2 SFT
LEFT JOIN [DW_TecStore].[dbo].[ProductDimension] PD ON SFT.ProductKey = PD.ProductKey --Buscar pares de la tabla derecha con la izquiera y si no hay correspondencia trae nulos
ORDER BY SFT.id_order
GO

/*--------------------------------------------------------------------------------------------------*/
	
-- Actualizar fechas para ClientDimension
WITH FechasModificadas(BirthDate) AS
(
	SELECT
		CASE WHEN BirthDate = '0000-00-00' THEN CONVERT(date, '01/01/1990')
		ELSE CONVERT(date, BirthDate)
		END AS BirthDate
	FROM ClientDimension
)
SELECT * INTO TempFechas FROM FechasModificadas
GO

UPDATE ClientDimension
SET BirthDate = NULL
GO

ALTER TABLE ClientDimension    --Alter table to uso formato varchar y cambia a date.
ALTER COLUMN BirthDate DATE NULL
GO

UPDATE ClientDimension
SET BirthDate = TempFechas.BirthDate FROM TempFechas
GO

DROP TABLE TempFechas
GO

/*--------------------------------------------------------------------------------------------------*/


-- Insertar IDCLIENTES faltantes en detallePedido
INSERT INTO [DW_TecStore].[dbo].[ClientDimension]
SELECT DISTINCT IDCLIENTE, id_gender, CONVERT(date, bdate) AS BirthDate, Dominio, ClasificacionCliente
FROM Pedidos
WHERE IDCLIENTE IS NOT NULL AND IDCLIENTE NOT IN (SELECT IDCLIENTE FROM [DW_TecStore].[dbo].[ClientDimension])
ORDER BY IDCLIENTE
GO

/*--------------------------------------------------------------------------------------------------*/

USE DW_TecStore
GO

-- Agregar AddressKey Faltantes
INSERT INTO AddressDimension
SELECT ISNULL(P.estado, '-') AS Estado, ISNULL(P.ciudad, '-') AS Ciudad, ISNULL(CONVERT(nvarchar, P.CP), '-') AS CP
FROM Pedidos P
LEFT JOIN AddressDimension AD ON ISNULL(P.estado, '-') = AD.Estado AND ISNULL(P.ciudad, '-') = AD.ciudad AND ISNULL(CONVERT(nvarchar, P.CP), '-') = AD.CP
WHERE AD.AddressKey IS NULL
ORDER BY id_order
GO

/*--------------------------------------------------------------------------------------------------*/

--Medir tabla no solo por pedido sino por orden puesta.

CREATE TABLE OrderFact
(
	id_order INT,
	IDCLIENTE INT,
	AddressKey INT,
	DateID Date,
	CECO FLOAT,
	TDC FLOAT,
	CuponesMMG FLOAT,
	GC FLOAT,
	Total MONEY,
	Transportista VARCHAR(150),
	Invitado VARCHAR(100)
	PRIMARY KEY (id_order),
	FOREIGN KEY (IDCLIENTE) REFERENCES ClientDimension(IDCLIENTE),
	FOREIGN KEY (AddressKey) REFERENCES AddressDimension(AddressKey),
	FOREIGN KEY (DateID) REFERENCES DateDimension(DateID)
)
GO


/*--------------------------------------------------------------------------------------------------*/

-- Agregar Fechas faltantes de Pedidos
INSERT INTO DateDimension
SELECT DISTINCT CONVERT(date, P.fecha) AS DateID2, YEAR(CONVERT(date, P.fecha)) AS Year, MONTH(CONVERT(date, P.fecha)) AS Month, DAY(CONVERT(date, P.fecha)) AS Day,
	DATENAME(WEEKDAY, CONVERT(date, P.fecha)) AS DayOfWeek, DATENAME(MONTH, CONVERT(date, P.fecha)) AS CalendarMonth, 0 AS HolidayIndicator,
	CHOOSE(DATEPART(WEEKDAY, CONVERT(date, fecha)), 'Weekend', 'Weekday', 'Weekday', 'Weekday', 'Weekday', 'Weekday', 'Weekend') AS WeekendIndicator
FROM Pedidos P
JOIN AddressDimension AD ON ISNULL(P.estado, '-') = AD.Estado AND ISNULL(P.ciudad, '-') = AD.ciudad AND ISNULL(CONVERT(nvarchar, P.CP), '-') = AD.CP
LEFT JOIN DateDimension DD ON CONVERT(date, P.fecha) = DD.DateID
WHERE DD.DateID IS NULL
ORDER BY DateID2
GO

/*--------------------------------------------------------------------------------------------------*/

-- Insertar valores a ORDERFACT
INSERT INTO OrderFact
SELECT id_order, IDCLIENTE, AD.AddressKey, CONVERT(date, fecha) AS DateID, CECO, TDC, CuponesMMP, GC, Total, Transportista, Invitado
FROM Pedidos P
JOIN AddressDimension AD ON ISNULL(P.estado, '-') = AD.Estado AND ISNULL(P.ciudad, '-') = AD.ciudad AND ISNULL(CONVERT(nvarchar, P.CP), '-') = AD.CP
ORDER BY id_order
GO

/*--------------------------------------------------------------------------------------------------*/

-- Crear tabla con Holidays
create FUNCTION [dbo].[ShiftHolidayToWorkday](@date date)   --@es variable 
RETURNS date
AS
BEGIN
    IF DATENAME( dw, @Date ) = 'Saturday'
        SET @Date = DATEADD(day, - 1, @Date)

    ELSE IF DATENAME( dw, @Date ) = 'Sunday'
        SET @Date = DATEADD(day, 1, @Date)

    RETURN @date
END
GO

create FUNCTION [dbo].[GetHoliday](@date date)
RETURNS varchar(50)
AS
BEGIN
    declare @s varchar(50)

    SELECT @s = CASE
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]  ) + '-01-01') =
             @date THEN 'New Year'
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]+1) + '-01-01') =
             @date THEN 'New Year'
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]  ) + '-07-04') =
             @date THEN 'Independence Day'
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]  ) + '-12-25') =
             @date THEN 'Christmas Day'
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]) + '-12-31') =
             @date THEN 'New Years Eve'
        WHEN dbo.ShiftHolidayToWorkday(CONVERT(varchar, [Year]) + '-11-11') =
             @date THEN 'Veteran''s Day'

        WHEN [Month] = 1  AND [DayOfMonth] BETWEEN 15 AND 21 AND [DayName] = 'Monday'
              THEN 'Martin Luther King Day'
        WHEN [Month] = 5  AND [DayOfMonth] >= 25             
              AND [DayName] = 'Monday' THEN 'Memorial Day'
        WHEN [Month] = 9  AND [DayOfMonth] <= 7              
              AND [DayName] = 'Monday' THEN 'Labor Day'
        WHEN [Month] = 11 AND [DayOfMonth] BETWEEN 22 AND 28 AND [DayName] = 'Thursday' 
              THEN 'Thanksgiving Day'
        WHEN [Month] = 11 AND [DayOfMonth] BETWEEN 23 AND 29 AND [DayName] = 'Friday' 
              THEN 'Day After Thanksgiving'
        ELSE NULL END
    FROM (
        SELECT
            [Year] = YEAR(@date),
            [Month] = MONTH(@date),
            [DayOfMonth] = DAY(@date),
            [DayName]   = DATENAME(weekday,@date)
    ) c

    RETURN @s
END
GO

create FUNCTION [dbo].GetHolidays(@year int)
RETURNS TABLE 
AS
RETURN (  
    select dt, dbo.GetHoliday(dt) as Holiday
    from (
        select dateadd(day, number, convert(varchar,@year) + '-01-01') dt
        from master..spt_values 
        where type='p' 
        ) d
    where year(dt) = @year and dbo.GetHoliday(dt) is not null
)
GO

create proc UpdateHolidaysTable
as

if not exists(select TABLE_NAME from INFORMATION_SCHEMA.TABLES where TABLE_NAME = 'Holidays')
    create table Holidays(dt date primary key clustered, Holiday varchar(50))

declare @year int
set @year = 1990

while @year < year(GetDate()) + 20
begin
    insert into Holidays(dt, Holiday)
    select a.dt, a.Holiday
    from dbo.GetHolidays(@year) a
        left join Holidays b on b.dt = a.dt
    where b.dt is null

    set @year = @year + 1
end
GO

EXEC UpdateHolidaysTable
GO

/*--------------------------------------------------------------------------------------------------*/
-- Update de las fechas que son holidays
UPDATE DateDimension
SET HolidayIndicator = CASE WHEN Holiday IS NULL THEN 0
	ELSE 1 END
FROM DateDimension DD
LEFT JOIN Holidays H ON DD.DateID = H.dt
GO

/*----------------------------------------------------------------------------------------------*/
-- Crear Tabla de AgeDimension
CREATE TABLE AgeDimension
(
	id_age INT IDENTITY(1,1),
	Year INT,
	Clasificacion VARCHAR(50)
	PRIMARY KEY (id_age)
)
GO

-- Generar AgeDimension
DECLARE @StartDate DATE, @EndDate DATE;
SELECT @StartDate =  MIN(BirthDate) FROM ClientDimension;
SELECT @EndDate = MAX(BirthDate) FROM ClientDimension;

WITH ListDates(AllDates) AS    --Tabla tempora se está implementando como cilo 
(	
	SELECT @StartDate AS DATE
    UNION ALL --Union all acumular resoltados de dos sentencias select 
    SELECT DATEADD(YEAR,1,AllDates)
    FROM ListDates    --
    WHERE AllDates < @EndDate
)
INSERT INTO AgeDimension
SELECT DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) AS Year,
	CASE WHEN DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) > 17 AND DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) < 30 THEN 'Adulto Joven'
	WHEN DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) > 29 AND DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) < 65 THEN 'Adulto'
	WHEN DATEDIFF(YEAR, LD.AllDates, CONVERT(date, GETDATE())) > 64 THEN 'Adulto Mayor' END AS Clasificacion
FROM ListDates LD
ORDER BY Year
OPTION(MAXRECURSION 10000)
GO

/*--------------------------------------------------------------------------------------------------*/

-- Crear Campo de AgeKey en SalesFact
ALTER TABLE SalesFact
ADD AgeKey INT
GO

-- Insertar Datos en AgeKey
UPDATE SalesFact
SET AgeKey = AD.id_age
	FROM SalesFact SF
	JOIN ClientDimension CD ON SF.IDCLIENTE = CD.IDCLIENTE
	JOIN AgeDimension AD ON DATEDIFF(YEAR, CD.BirthDate, CONVERT(date, GETDATE())) = AD.Year
GO

-- Generar FK con AgeKey
ALTER TABLE SalesFact  --modificiar cosas dentro de tablas 
ADD CONSTRAINT FK_SalesFact_AgeDim
FOREIGN KEY (AgeKey) REFERENCES AgeDimension(id_age)
GO

/*--------------------------------------------------------------------------------------------------*/

-- Crear Campo de AgeKey en OrderFact

-- Crear Campo de AgeKey en OrderFact
ALTER TABLE OrderFact
ADD AgeKey INT
GO

-- Insertar Datos en AgeKey
UPDATE OrderFact
SET AgeKey = AD.id_age
	FROM OrderFact OrF
	LEFT JOIN ClientDimension CD ON OrF.IDCLIENTE = CD.IDCLIENTE
	LEFT JOIN AgeDimension AD ON DATEDIFF(YEAR, CD.BirthDate, CONVERT(date, GETDATE())) = AD.Year
GO

-- Generar FK con AgeKey
ALTER TABLE OrderFact
ADD CONSTRAINT FK_OrderFact_AgeDim  --Comando para crear una llave, principalmente se usa para FK
FOREIGN KEY (AgeKey) REFERENCES AgeDimension(id_age)
GO
