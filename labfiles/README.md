# Lab-Files

This folder contains all synthetic data assets used throughout the **Transform Enterprise Data to Decisions** lab.  
Load these files onto the jump-box (e.g. under `C:\Users\LabUser\Desktop\Data\`) before participants start the exercises.

---

## Files

| File | Used In | Description |
|---|---|---|
| `sales_transactions.csv` | Exercises 2, 3, 4, 6 | 8,600+ sales records for Contoso across 5 regions and 4 months (Oct 2023 – Jan 2024). Reflects a −15 % revenue drop in the NORTH region in January 2024. |
| `inventory_data.csv` | Exercises 2, 3, 4 | 20 products across 5 warehouse regions. NORTH has 8 products below reorder point, EAST has 5, SOUTH has 2. |
| `customer_feedback.csv` | Exercises 2, 3, 4 | 2,000 customer feedback entries across 5 regions. NORTH has the lowest average rating (~3.1). |
| `sales_drop_simulation.csv` | Exercise 6 | 8 simulation rows representing a dramatic North-region sales drop in February 2024. Upload this file in Task 6.1 to trigger the end-to-end validation scenario. |
| `Contoso_Business_Brief.pdf` | Exercises 1, 4 | Business context document used in Task 1.1 and indexed into the Azure AI Search RAG pipeline in Task 4.4. |

---

## OneLake Target Paths

When loading data into the Fabric Lakehouse (`ContosoLakehouse`), place files in these paths:

```
Files/
└── raw/
    ├── sales/
    │   ├── sales_transactions.csv
    │   └── sales_drop_simulation.csv   ← upload only in Exercise 6
    ├── inventory/
    │   └── inventory_data.csv
    └── feedback/
        └── customer_feedback.csv
```

The `Contoso_Business_Brief.pdf` is uploaded directly to Azure AI Foundry in **Exercise 4, Task 4.4** (Step 1 → "Upload files").

---

## Schema Reference

### `sales_transactions.csv`

| Column | Type | Notes |
|---|---|---|
| `TransactionID` | Text | Unique, format `TXN-XXXXXX` |
| `SaleDate` | Date (`yyyy-MM-dd`) | Oct 2023 – Jan 2024 |
| `Region` | Text | `NORTH` / `SOUTH` / `EAST` / `WEST` / `CENTRAL` |
| `ProductID` | Text | `PROD-101` to `PROD-120` |
| `Quantity` | Integer | 1 – 5 |
| `Revenue` | Decimal | Unit price × quantity with slight variation |
| `CustomerID` | Text | `CUST-1001` to `CUST-2999` |

### `inventory_data.csv`

| Column | Type | Notes |
|---|---|---|
| `ProductID` | Text | `PROD-101` to `PROD-120` (one row per product) |
| `ProductName` | Text | Descriptive product name |
| `Category` | Text | `Electronics` / `Furniture` / `Apparel` / `Office Supplies` |
| `StockLevel` | Integer | Current stock on hand |
| `ReorderPoint` | Integer | Minimum stock before restocking is triggered |
| `WarehouseRegion` | Text | Warehouse the product is stored in |

### `customer_feedback.csv`

| Column | Type | Notes |
|---|---|---|
| `FeedbackID` | Text | Unique, format `FB-XXXXX` |
| `CustomerID` | Text | Matches `CustomerID` in sales data |
| `FeedbackDate` | Date (`yyyy-MM-dd`) | Oct 2023 – Jan 2024 |
| `Rating` | Integer | 1 – 5 |
| `Comments` | Text | Free-text sentiment comments |
| `Region` | Text | Region the feedback belongs to |

### `sales_drop_simulation.csv`

Same schema as `sales_transactions.csv`. IDs use the `SIM-XXX` prefix.  
Revenue total is ~£8,800 — approximately 30 % lower than the North region's typical weekly run rate, which will trigger the configured Power BI alerts.

---

## Key Data Characteristics (aligned to lab exercises)

| Metric | Value | Exercise Reference |
|---|---|---|
| NORTH Jan 2024 revenue | ~£425,000 | Exercise 4 – `LoadFabricContext` node |
| NORTH Dec 2023 revenue | ~£500,000 | Exercise 4 – revenue_change_pct = −15 % |
| SOUTH Jan 2024 revenue | ~£610,000 | Exercise 4 – positive trend |
| EAST Jan 2024 revenue | ~£390,000 | Exercise 4 – revenue_change_pct = −7.1 % |
| NORTH avg customer rating | ~3.1 / 5 | Exercise 4 – avg_rating |
| SOUTH avg customer rating | ~4.2 / 5 | Exercise 4 – avg_rating |
| Products below reorder (NORTH) | 8 | Exercise 3 – alert threshold = 5 |
| Overall customer satisfaction | ~3.2 / 5 | Exercise 1 – KPI baseline |
