# 🛒 Grocery POS Database Management System

> **A robust, 3NF-normalized database solution designed for high-volume grocery retail, modeled after the SAPO Omnichannel architecture.**

![SQL Server](https://img.shields.io/badge/Database-SQL%20Server-CC2927?style=flat&logo=microsoft-sql-server)
![Status](https://img.shields.io/badge/Status-Completed-success)
![Context](https://img.shields.io/badge/Context-University%20Project-blue)

## 📖 Project Overview

This project is a relational database system designed to digitize the operations of local grocery stores and mini-marts. Based on the business model of **SAPO** (a leading retail platform in Vietnam), this system addresses critical operational challenges such as complex unit conversions (e.g., selling bottles vs. cartons), inventory mismanagement ("phantom inventory"), and financial auditing.

The system provides a comprehensive backend solution for managing **Sales**, **Inventory**, **Customers**, and **Store Operations**, ensuring data integrity through strict constraints and advanced server-side automation (Triggers).

## 🚩 The Problem: "The Manual Store Chaos"

Local mini-marts often rely on manual notebooks or disconnected tools, leading to three major pain points identified in our research:
1.  **Phantom Inventory:** Stores buy in bulk (Cartons) but sell in units (Packs/Bottles). Without a system to track this conversion, inventory counts are rarely accurate
2.  **Cash Discrepancies:** Without linking sales to specific employee shifts, owners cannot reconcile the physical cash drawer against actual revenue, leading to undetected losses.
3.  **Financial Blind Spots:** Manual debt tracking ("Ghi nợ") and slow checkout processes during peak hours hurt profitability.

## 💡 Key Features & Solution Architecture

To solve these issues, we designed a database with **14 tables** organized into 4 logical modules:

### 1. 🔄 Recursive Inventory Logic 
We solved the complex **Unit Conversion** problem using a self-referencing relationship in the `ProductVariants` table.
**Logic:** A "Pack" variant links back to a "Base Unit" (Bottle) via a `BaseVariantID` and a `ConversionRate`.
* **Result:** Selling a pack automatically deducts the correct number of single units from inventory, maintaining a "Single Source of Truth."

### 2. 🛡️ Automated Data Integrity (Database Triggers)
We moved critical business logic from the application layer to the database layer using T-SQL Triggers:
**Stock Guardrail:** Prevents transactions if `OrderQuantity > AvailableStock` (No negative inventory).
**Auto-Deduct:** Automatically converts units and reduces stock only when an order is finalized.
**Financial Accuracy:** Automatically recalculates order totals when line items are modified to prevent calculation errors.

### 3. 📊 Optimized Reporting (OLAP Strategy)
While transactional tables (`Orders`, `Customers`) are normalized to **3NF** to prevent redundancy, we strategically denormalized the `DailySaleReport` table. This pre-calculates revenue and profit, allowing for instant dashboard loading without slowing down live sales operations.

## 🗂️ Database Schema (ERD)

The system is built on Microsoft SQL Server. Below is a high-level overview of the core modules:

* **Inventory Module:** `Products`, `ProductVariants`, `Categories`
* **Sales Module:** `Orders` (Header), `OrderDetail` (Line Items), `Payment` (Financial Audit)
* **Operations Module:** `Employee`, `WorkShifts`, `Suppliers`, `PurchaseOrders`
* **Customer Module:** `Customer`, `CustomerGroup` (Dynamic Pricing)

*(See the `docs` folder for the full Entity Relationship Diagram)*

## 🚀 Technical Implementation

### Tech Stack
* **DBMS:** Microsoft SQL Server (T-SQL)
* **Tools:** SSMS (SQL Server Management Studio), dbdiagram.io
    IF EXISTS ( ... ) 
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR ('Error: Insufficient stock...', 16, 1);
    END
END
