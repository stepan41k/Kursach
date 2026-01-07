package main

import (
	"context"
	"fmt"
	"log"
	"math"
	"os"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// --- 1. STRUCТS (JSON DTOs) ---

type LoginRequest struct {
	Login    string `json:"login"`
	Password string `json:"password"`
}

type LoginResponse struct {
	Token string `json:"token"`
	User  struct {
		ID       int64  `json:"id"`
		Role     string `json:"role"`
		FullName string `json:"name"`
	} `json:"user"`
}

type Client struct {
	ID             int64     `json:"id"`
	FirstName      string    `json:"firstName"`
	LastName       string    `json:"lastName"`
	MiddleName     *string   `json:"middleName"` // Pointer for NULL handling
	PassportSeries string    `json:"passportSeries"`
	PassportNumber string    `json:"passportNumber"`
	PassportIssued *string   `json:"passportIssuedBy"`
	DateOfBirth    string    `json:"dateOfBirth"` // YYYY-MM-DD
	Address        string    `json:"address"`
	Phone          string    `json:"phone"`
	Email          *string   `json:"email"`
	CreatedAt      time.Time `json:"createdAt"`
}

type CreditProduct struct {
	ID            int     `json:"id"`
	Name          string  `json:"name"`
	MinAmount     float64 `json:"minAmount"`
	MaxAmount     float64 `json:"maxAmount"`
	MinTermMonths int     `json:"minTerm"`
	MaxTermMonths int     `json:"maxTerm"`
	InterestRate  float64 `json:"rate"`
	IsActive      bool    `json:"isActive"`
}

type LoanContract struct {
	ID             int64     `json:"id"`
	ContractNumber string    `json:"contractNumber"`
	ClientID       int64     `json:"clientId"`
	ClientName     string    `json:"clientName"` // Joined field
	ProductName    string    `json:"productName"` // Joined field
	Amount         float64   `json:"amount"`
	InterestRate   float64   `json:"interestRate"`
	TermMonths     int       `json:"termMonths"`
	StartDate      time.Time `json:"startDate"`
	EndDate        time.Time `json:"endDate"`
	Status         string    `json:"status"`
}

type RepaymentScheduleItem struct {
	ID               int64     `json:"id"`
	ContractID       int64     `json:"contractId"`
	PaymentDate      time.Time `json:"paymentDate"`
	PaymentAmount    float64   `json:"paymentAmount"`
	PrincipalAmount  float64   `json:"principal"`
	InterestAmount   float64   `json:"interest"`
	RemainingBalance float64   `json:"remainingBalance"`
	IsPaid           bool      `json:"isPaid"`
}

type IssueLoanRequest struct {
	ClientID   int64   `json:"clientId"`
	ProductID  int     `json:"productId"`
	Amount     float64 `json:"amount"`
	TermMonths int     `json:"termMonths"`
	EmployeeID int64   `json:"employeeId"`
}

// --- 2. DB CONNECTION (pgxpool) ---

var db *pgxpool.Pool

func initDB() {
	dbUrl := os.Getenv("DATABASE_URL")

	if dbUrl == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	config, err := pgxpool.ParseConfig(dbUrl)
	if err != nil {
		log.Fatal("Unable to parse DB URL:", err)
	}

	db, err = pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal("Unable to connect to database:", err)
	}

	// Проверка связи
	if err := db.Ping(context.Background()); err != nil {
		log.Fatal("Database ping failed:", err)
	}
	log.Println("Connected to PostgreSQL via pgxpool")
}

// --- 3. HANDLERS ---

func loginHandler(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request"})
		return
	}

	ctx := c.Request.Context()
	
	// SQL: Join users -> roles -> employees
	query := `
		SELECT u.id, u.password_hash, r.name, e.first_name, e.last_name
		FROM users u
		JOIN roles r ON u.role_id = r.id
		LEFT JOIN employees e ON u.id = e.user_id
		WHERE u.login = $1 AND u.is_active = true
	`

	var userID int64
	var pwdHash, roleName string
	var fName, lName *string // Use pointers for nullable columns

	err := db.QueryRow(ctx, query, req.Login).Scan(&userID, &pwdHash, &roleName, &fName, &lName)
	if err == pgx.ErrNoRows {
		c.JSON(401, gin.H{"error": "User not found"})
		return
	} else if err != nil {
		c.JSON(500, gin.H{"error": "Database error"})
		log.Println(err)
		return
	}

	// В продакшене: bcrypt.CompareHashAndPassword
	if req.Password != pwdHash {
		c.JSON(401, gin.H{"error": "Invalid password"})
		return
	}

	fullName := "System User"
	if fName != nil && lName != nil {
		fullName = fmt.Sprintf("%s %s", *fName, *lName)
	}

	resp := LoginResponse{
		Token: "demo-token-123",
		User: struct {
			ID       int64  `json:"id"`
			Role     string `json:"role"`
			FullName string `json:"name"`
		}{userID, roleName, fullName},
	}

	c.JSON(200, resp)
}

func getClients(c *gin.Context) {
	rows, err := db.Query(c.Request.Context(), `
		SELECT id, first_name, last_name, passport_series, passport_number, phone, address 
		FROM clients 
		ORDER BY created_at DESC
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var clients []Client
	for rows.Next() {
		var cl Client
		// Сканируем только нужные поля для списка
		if err := rows.Scan(&cl.ID, &cl.FirstName, &cl.LastName, &cl.PassportSeries, &cl.PassportNumber, &cl.Phone, &cl.Address); err != nil {
			log.Println("Scan error:", err)
			continue
		}
		clients = append(clients, cl)
	}
	c.JSON(200, clients)
}

func createClient(c *gin.Context) {
	var cl Client
	if err := c.ShouldBindJSON(&cl); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Парсинг даты
	dob, err := time.Parse("2006-01-02", cl.DateOfBirth)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid date format (YYYY-MM-DD)"})
		return
	}

	query := `
		INSERT INTO clients 
		(first_name, last_name, middle_name, passport_series, passport_number, passport_issued_by, date_of_birth, address, phone, email)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING id, created_at
	`
	
	err = db.QueryRow(c.Request.Context(), query, 
		cl.FirstName, cl.LastName, cl.MiddleName, 
		cl.PassportSeries, cl.PassportNumber, cl.PassportIssued, 
		dob, cl.Address, cl.Phone, cl.Email,
	).Scan(&cl.ID, &cl.CreatedAt)

	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to create client (possibly duplicate passport)"})
		log.Println(err)
		return
	}

	c.JSON(201, cl)
}

func getProducts(c *gin.Context) {
	rows, err := db.Query(c.Request.Context(), "SELECT id, name, min_amount, max_amount, min_term_months, max_term_months, interest_rate FROM credit_products WHERE is_active = true")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var products []CreditProduct
	for rows.Next() {
		var p CreditProduct
		rows.Scan(&p.ID, &p.Name, &p.MinAmount, &p.MaxAmount, &p.MinTermMonths, &p.MaxTermMonths, &p.InterestRate)
		products = append(products, p)
	}
	c.JSON(200, products)
}

// === MAIN BUSINESS LOGIC ===

func issueLoan(c *gin.Context) {
	var req IssueLoanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid JSON"})
		return
	}
	ctx := c.Request.Context()

	// 1. Проверяем продукт и лимиты
	var p CreditProduct
	err := db.QueryRow(ctx, "SELECT min_amount, max_amount, interest_rate FROM credit_products WHERE id = $1", req.ProductID).
		Scan(&p.MinAmount, &p.MaxAmount, &p.InterestRate)
	
	if err != nil {
		c.JSON(404, gin.H{"error": "Product not found"})
		return
	}

	if req.Amount < p.MinAmount || req.Amount > p.MaxAmount {
		c.JSON(400, gin.H{"error": "Amount is out of product limits"})
		return
	}

	// 2. Расчет аннуитета
	monthlyRate := p.InterestRate / 12 / 100
	powFactor := math.Pow(1+monthlyRate, float64(req.TermMonths))
	annuity := req.Amount * (monthlyRate * powFactor) / (powFactor - 1)
	annuity = math.Round(annuity*100) / 100 // Округление до копеек

	// 3. START TRANSACTION
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx begin failed"})
		return
	}
	// Defer rollback in case of panic or error (safe to call if committed)
	defer tx.Rollback(ctx)

	// A. Insert Loan Contract
	contractNumber := fmt.Sprintf("LN-%d-%d", time.Now().Unix(), req.ClientID)
	var contractID int64
	startDate := time.Now()
	endDate := startDate.AddDate(0, req.TermMonths, 0)

	err = tx.QueryRow(ctx, `
		INSERT INTO loan_contracts 
		(contract_number, client_id, product_id, approved_by_employee_id, amount, interest_rate, term_months, start_date, end_date, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'active'::contract_status)
		RETURNING id
	`, contractNumber, req.ClientID, req.ProductID, req.EmployeeID, req.Amount, p.InterestRate, req.TermMonths, startDate, endDate).
		Scan(&contractID)

	if err != nil {
		log.Println("Insert contract failed:", err)
		c.JSON(500, gin.H{"error": "Failed to create contract"})
		return
	}

	// B. Generate Schedule (Loop insert)
	balance := req.Amount
	currentDate := startDate

	stmt := `
		INSERT INTO repayment_schedule 
		(contract_id, payment_date, payment_amount, principal_amount, interest_amount, remaining_balance)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	for i := 1; i <= req.TermMonths; i++ {
		currentDate = currentDate.AddDate(0, 1, 0)

		interest := balance * monthlyRate
		interest = math.Round(interest*100) / 100

		principal := annuity - interest
		
		// Корректировка последнего платежа
		if i == req.TermMonths || principal > balance {
			principal = balance
			annuity = principal + interest
		}

		balance -= principal
		if balance < 0 { balance = 0 }

		_, err := tx.Exec(ctx, stmt, contractID, currentDate, annuity, principal, interest, balance)
		if err != nil {
			log.Println("Schedule insert failed:", err)
			c.JSON(500, gin.H{"error": "Failed to generate schedule"})
			return
		}
	}

	// C. Log Operation
	_, err = tx.Exec(ctx, `
		INSERT INTO operations (contract_id, employee_id, operation_type, amount, description)
		VALUES ($1, $2, 'issue'::operation_type, $3, 'Credit issued via system')
	`, contractID, req.EmployeeID, req.Amount)

	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to log operation"})
		return
	}

	// 4. COMMIT
	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(201, gin.H{"message": "Loan issued", "contractId": contractID, "contractNumber": contractNumber})
}

func getLoans(c *gin.Context) {
	// JOIN для получения читаемых имен
	query := `
		SELECT lc.id, lc.contract_number, lc.amount, lc.status, lc.start_date,
		       c.first_name || ' ' || c.last_name as client_name,
		       cp.name as product_name
		FROM loan_contracts lc
		JOIN clients c ON lc.client_id = c.id
		JOIN credit_products cp ON lc.product_id = cp.id
		ORDER BY lc.created_at DESC
	`
	rows, err := db.Query(c.Request.Context(), query)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var loans []LoanContract
	for rows.Next() {
		var l LoanContract
		// contract_status это enum, pgx сканирует его в string нормально
		rows.Scan(&l.ID, &l.ContractNumber, &l.Amount, &l.Status, &l.StartDate, &l.ClientName, &l.ProductName)
		loans = append(loans, l)
	}
	c.JSON(200, loans)
}

func getSchedule(c *gin.Context) {
	id := c.Param("id")
	rows, err := db.Query(c.Request.Context(), `
		SELECT id, payment_date, payment_amount, principal_amount, interest_amount, remaining_balance, is_paid
		FROM repayment_schedule
		WHERE contract_id = $1
		ORDER BY payment_date ASC
	`, id)
	
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var schedule []RepaymentScheduleItem
	for rows.Next() {
		var item RepaymentScheduleItem
		rows.Scan(&item.ID, &item.PaymentDate, &item.PaymentAmount, &item.PrincipalAmount, &item.InterestAmount, &item.RemainingBalance, &item.IsPaid)
		schedule = append(schedule, item)
	}
	c.JSON(200, schedule)
}

func getEmployeesHandler(c *gin.Context) {
	// В реальной системе тут нужна проверка прав (Middleware), 
    // но пока просто отдаем список
	rows, err := db.Query(c.Request.Context(), `
		SELECT e.id, e.first_name, e.last_name, e.position, u.login, r.name as role
		FROM employees e
		JOIN users u ON e.user_id = u.id
		JOIN roles r ON u.role_id = r.id
		ORDER BY e.id DESC
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var employees []gin.H
	for rows.Next() {
		var id int
		var fn, ln, pos, login, role string
		if err := rows.Scan(&id, &fn, &ln, &pos, &login, &role); err != nil {
			continue
		}
		employees = append(employees, gin.H{
			"id": id, "firstName": fn, "lastName": ln, 
			"position": pos, "login": login, "role": role,
		})
	}
	c.JSON(200, employees)
}

func main() {
	initDB()
	// Закрываем пул при выходе (хотя в веб-сервере это редко нужно)
	defer db.Close()

	r := gin.Default()
	r.Use(cors.New(cors.Config{
		AllowOrigins: []string{"*"},
		AllowMethods: []string{"GET", "POST", "OPTIONS"},
		AllowHeaders: []string{"Content-Type"},
	}))

	api := r.Group("/api")
	{
		api.POST("/login", loginHandler)
		api.GET("/clients", getClients)
		api.POST("/clients", createClient)
		api.GET("/products", getProducts)
		api.POST("/loans", issueLoan)
		api.GET("/loans", getLoans)
		api.GET("/loans/:id/schedule", getSchedule)
		api.GET("/employees", getEmployeesHandler)
	}

	r.Run(":8080")
}