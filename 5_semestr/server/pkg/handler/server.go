package handler

import (
	"context"
	"fmt"
	"log"
	"math"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/backup"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/auth"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/mail"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/password"
	"github.com/stepan41k/Kursach/5_semestr/pkg/models"
)

type HandlerDriver struct {
	db *pgxpool.Pool
}

func NewHandlerDriver(db *pgxpool.Pool) *HandlerDriver {
	return &HandlerDriver{
		db: db,
	}
}

func (h *HandlerDriver) RegisterHandler(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Ошибка валидации данных", "details": err.Error()})
		return
	}

	ctx := c.Request.Context()

	// Начинаем транзакцию
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx failed"})
		return
	}
	defer tx.Rollback(ctx)

	// 1. Находим ID роли 'manager' (или создаем, если нет)
	var roleID int
	// Пытаемся найти роль manager
	err = tx.QueryRow(ctx, "SELECT id FROM roles WHERE name = 'manager'").Scan(&roleID)
	if err != nil {
		// Если роли нет, ошибка (в реальности она должна быть в init.sql)
		c.JSON(500, gin.H{"error": "Role 'manager' not found in DB. Please run init sql."})
		return
	}

	// 2. Создаем User
	var userID int64
	// is_active = true
	err = tx.QueryRow(ctx, `
		INSERT INTO users (role_id, login, password_hash, is_active)
		VALUES ($1, $2, $3, true)
		RETURNING id
	`, roleID, req.Login, req.Password).Scan(&userID)

	if err != nil {
		c.JSON(409, gin.H{"error": "Login already exists"})
		return
	}

	// 3. Создаем Employee
	_, err = tx.Exec(ctx, `
		INSERT INTO employees (user_id, first_name, last_name, position, email)
		VALUES ($1, $2, $3, $4, $5)
	`, userID, req.FirstName, req.LastName, req.Position, req.Email)

	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to create employee profile"})
		return
	}

	adminID, _ := c.Get("userId") // Получаем ID админа из middleware

	LogAction(ctx, tx, adminID.(int64), "REGISTER_EMPLOYEE", "employees", userID, map[string]string{
		"login": req.Login,
		"role":  "manager",
		"name":  fmt.Sprintf("%s %s", req.FirstName, req.LastName),
	})

	// Подтверждаем транзакцию
	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(201, gin.H{"message": "Employee registered successfully"})
}

func (h *HandlerDriver) LoginHandler(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request"})
		return
	}

	ctx := c.Request.Context()

	// Обновленный SQL: добавили e.email в выборку
	query := `
		SELECT 
			u.id, 
			u.password_hash, 
			r.name, 
			COALESCE(e.first_name, c.first_name), 
			COALESCE(e.last_name, c.last_name),  
			COALESCE(e.email, c.email)            
		FROM users u
		JOIN roles r ON u.role_id = r.id
		LEFT JOIN employees e ON u.id = e.user_id
		LEFT JOIN clients c ON u.id = c.user_id
		WHERE u.login = $1 AND u.is_active = true
	`

	var userID int64
	var pwdHash, roleName string
	var fName, lName, email *string // email может быть NULL (указатель)

	// Сканируем email
	err := h.db.QueryRow(ctx, query, req.Login).Scan(&userID, &pwdHash, &roleName, &fName, &lName, &email)
	if err != nil {
		c.JSON(401, gin.H{"error": "User not found"})
		return
	}

	// Проверка пароля (в реальном проекте используйте bcrypt!)
	if req.Password != pwdHash {
		c.JSON(401, gin.H{"error": "Invalid password"})
		return
	}

	// ... (Код генерации JWT токена остается прежним) ...
	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &auth.Claims{
		UserID: userID,
		Role:   roleName,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(auth.JWTKey)
	if err != nil {
		c.JSON(500, gin.H{"error": "Could not generate token"})
		return
	}

	fullName := "System User"
	if fName != nil && lName != nil {
		fullName = fmt.Sprintf("%s %s", *fName, *lName)
	}

	// === ОТПРАВКА ПИСЬМА ===
	// Запускаем в отдельном потоке (goroutine), чтобы не тормозить ответ клиенту
	if email != nil && *email != "" {
		userIP := c.ClientIP()
		targetEmail := *email
		// Запускаем асинхронно
		go mail.SendLoginEmail(targetEmail, fullName, userIP)
	}
	// =======================

	resp := models.LoginResponse{
		Token: tokenString,
		User: struct {
			ID       int64  `json:"id"`
			Role     string `json:"role"`
			FullName string `json:"name"`
		}{userID, roleName, fullName},
	}

	c.JSON(200, resp)
}

func (h *HandlerDriver) GetClients(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT id, first_name, last_name, passport_series, passport_number, phone, address 
		FROM clients 
		ORDER BY created_at DESC
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var clients []models.Client
	for rows.Next() {
		var cl models.Client
		// Сканируем только нужные поля для списка
		if err := rows.Scan(&cl.ID, &cl.FirstName, &cl.LastName, &cl.PassportSeries, &cl.PassportNumber, &cl.Phone, &cl.Address); err != nil {
			log.Println("Scan error:", err)
			continue
		}
		clients = append(clients, cl)
	}
	c.JSON(200, clients)
}

func (h *HandlerDriver) CreateClient(c *gin.Context) {
	var req models.CreateClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Ошибка валидации данных", "details": err.Error()})
		return
	}

	dob, err := time.Parse("2006-01-02", req.DateOfBirth)
	if err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат даты"})
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx start failed"})
		return
	}
	defer tx.Rollback(ctx)

	// === ГЕНЕРАЦИЯ УЧЕТНЫХ ДАННЫХ ===
	// Логин = Паспорт (только цифры)
	genLogin := strings.ReplaceAll(req.PassportSeries+req.PassportNumber, " ", "")
	// Пароль = Случайные 8 символов
	genPassword := password.GenerateRandomPassword(8)
	// ================================

	// 1. Создаем пользователя
	var roleID int
	_ = tx.QueryRow(ctx, "SELECT id FROM roles WHERE name = 'client'").Scan(&roleID)

	var userID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO users (role_id, login, password_hash, is_active)
		VALUES ($1, $2, $3, true) 
		RETURNING id
	`, roleID, genLogin, genPassword).Scan(&userID)

	if err != nil {
		c.JSON(409, gin.H{"error": "Клиент с таким паспортом (логином) уже существует"})
		return
	}

	// 2. Создаем профиль клиента
	var clientID int64
	var createdAt time.Time

	query := `
		INSERT INTO clients 
		(user_id, first_name, last_name, middle_name, passport_series, passport_number, passport_issued_by, date_of_birth, address, phone, email)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id, created_at
	`

	err = tx.QueryRow(ctx, query,
		userID, req.FirstName, req.LastName, req.MiddleName,
		req.PassportSeries, req.PassportNumber, req.PassportIssued,
		dob, req.Address, req.Phone, req.Email,
	).Scan(&clientID, &createdAt)

	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка создания профиля клиента"})
		return
	}

	// Логирование
	operatorID, _ := c.Get("userId")
	var opID int64 = 0
	if operatorID != nil {
		opID = operatorID.(int64)
	}

	LogAction(ctx, tx, opID, "CREATE_CLIENT", "clients", clientID, map[string]string{
		"login": genLogin,
		"name":  fmt.Sprintf("%s %s", req.LastName, req.FirstName),
		"email": req.Email,
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	// === ОТПРАВКА ПИСЬМА ===
	// Отправляем сгенерированные данные
	go mail.SendClientWelcomeEmail(
		req.Email,
		fmt.Sprintf("%s %s", req.FirstName, req.LastName),
		genLogin,
		genPassword,
	)

	c.JSON(201, gin.H{"message": "Client created", "id": clientID})
}

func (h *HandlerDriver) GetProducts(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT id, name, min_amount, max_amount, min_term_months, max_term_months, interest_rate FROM credit_products WHERE is_active = true")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var products []models.CreditProduct
	for rows.Next() {
		var p models.CreditProduct
		rows.Scan(&p.ID, &p.Name, &p.MinAmount, &p.MaxAmount, &p.MinTermMonths, &p.MaxTermMonths, &p.InterestRate)
		products = append(products, p)
	}
	c.JSON(200, products)
}

// === MAIN BUSINESS LOGIC ===

func (h *HandlerDriver) IssueLoan(c *gin.Context) {
	var req models.IssueLoanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid JSON"})
		return
	}
	ctx := c.Request.Context()

	// 1. Проверяем продукт и лимиты
	var p models.CreditProduct
	err := h.db.QueryRow(ctx, "SELECT min_amount, max_amount, interest_rate FROM credit_products WHERE id = $1", req.ProductID).
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
	tx, err := h.db.Begin(ctx)
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
		(contract_number, client_id, product_id, approved_by_employee_id, balance, amount, interest_rate, term_months, start_date, end_date, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'active'::contract_status)
		RETURNING id
	`, contractNumber, req.ClientID, req.ProductID, req.EmployeeID, req.Amount, req.Amount, p.InterestRate, req.TermMonths, startDate, endDate).
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
		if balance < 0 {
			balance = 0
		}

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

	LogAction(ctx, tx, req.EmployeeID, "ISSUE_LOAN", "loan_contracts", contractID, map[string]string{
		"amount":   fmt.Sprintf("%.2f", req.Amount),
		"term":     fmt.Sprintf("%d", req.TermMonths),
		"contract": contractNumber,
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(201, gin.H{"message": "Loan issued", "contractId": contractID, "contractNumber": contractNumber})
}

func (h *HandlerDriver) GetLoans(c *gin.Context) {
	// ИСПРАВЛЕНИЕ: Добавили lc.interest_rate и lc.term_months в запрос
	query := `
		SELECT lc.id, lc.contract_number, lc.amount, lc.status, lc.start_date,
		       lc.interest_rate, lc.term_months, lc.balance, 
		       c.first_name || ' ' || c.last_name as client_name,
		       cp.name as product_name
		FROM loan_contracts lc
		JOIN clients c ON lc.client_id = c.id
		JOIN credit_products cp ON lc.product_id = cp.id
		ORDER BY lc.created_at DESC
	`
	rows, err := h.db.Query(c.Request.Context(), query)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var loans []gin.H
	for rows.Next() {
		var id int64
		var contractNum, status, clientName, prodName string
		var amount, balance, rate float64
		var startDate time.Time
		var term int

		// Сканируем новые поля
		err := rows.Scan(&id, &contractNum, &amount, &status, &startDate, &rate, &term, &balance, &clientName, &prodName)
		if err != nil {
			log.Println("Scan error:", err)
			continue
		}
		
		loans = append(loans, gin.H{
			"id": id, 
			"contractNumber": contractNum, 
			"amount": amount,
			"balance": balance,
			"status": status, 
			"startDate": startDate,
			"clientName": clientName,
			"productName": prodName,
			"interestRate": rate,
			"termMonths": term,
		})
	}
	
	if loans == nil {
		loans = []gin.H{}
	}
	c.JSON(200, loans)
}

func (h *HandlerDriver) GetSchedule(c *gin.Context) {
	id := c.Param("id")
	rows, err := h.db.Query(c.Request.Context(), `
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

	var schedule []models.RepaymentScheduleItem
	for rows.Next() {
		var item models.RepaymentScheduleItem
		rows.Scan(&item.ID, &item.PaymentDate, &item.PaymentAmount, &item.PrincipalAmount, &item.InterestAmount, &item.RemainingBalance, &item.IsPaid)
		schedule = append(schedule, item)
	}
	c.JSON(200, schedule)
}

func (h *HandlerDriver) GetEmployeesHandler(c *gin.Context) {
	// В реальной системе тут нужна проверка прав (Middleware),
	// но пока просто отдаем список
	rows, err := h.db.Query(c.Request.Context(), `
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

func (h *HandlerDriver) GetLogsHandler(c *gin.Context) {
	action := c.Query("action")
	fromDate := c.Query("from")

	// УЛУЧШЕННЫЙ SQL:
	// COALESCE заменяет NULL на дефолтные значения прямо в базе,
	// чтобы Go не ругался при сканировании.
	sqlQuery := `
		SELECT 
			a.id, 
			a.action_type, 
			COALESCE(a.entity_name, 'system'), 
			COALESCE(a.entity_id, 0), 
			a.created_at, 
			COALESCE(a.new_values, '{}'::jsonb),
			u.login, 
			e.first_name, 
			e.last_name
		FROM audit_logs a
		LEFT JOIN users u ON a.user_id = u.id
		LEFT JOIN employees e ON u.id = e.user_id
		WHERE 1=1
	`
	args := []interface{}{}
	argCounter := 1

	if action != "" {
		sqlQuery += fmt.Sprintf(" AND a.action_type = $%d", argCounter)
		args = append(args, action)
		argCounter++
	}
	if fromDate != "" {
		sqlQuery += fmt.Sprintf(" AND a.created_at >= $%d", argCounter)
		args = append(args, fromDate)
		argCounter++
	}

	sqlQuery += " ORDER BY a.created_at DESC LIMIT 50"

	rows, err := h.db.Query(c.Request.Context(), sqlQuery, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var logs []gin.H
	for rows.Next() {
		var id, entID int64
		var act, ent string
		var details map[string]interface{}
		var ts time.Time
		// login, fn, ln остаются указателями, так как LEFT JOIN может вернуть NULL для всей таблицы юзера
		var login, fn, ln *string 

		err := rows.Scan(&id, &act, &ent, &entID, &ts, &details, &login, &fn, &ln)
		if err != nil {
			// Если ошибка все еще есть, выведем её в лог контейнера
			log.Printf("Error scanning log row ID %d: %v", id, err)
			continue
		}

		userName := "Система/Неизвестный"
		if login != nil {
			userName = *login
			if fn != nil && ln != nil {
				userName = fmt.Sprintf("%s %s (%s)", *ln, *fn, *login)
			}
		}

		logs = append(logs, gin.H{
			"id": id, "action": act, "entity": ent, "entityId": entID,
			"date": ts, "details": details, "user": userName,
		})
	}

	if logs == nil {
		logs = []gin.H{}
	}
	c.JSON(200, logs)
}

func LogAction(ctx context.Context, tx pgx.Tx, userID int64, action string, entity string, entityID int64, details map[string]string) {
	_, err := tx.Exec(ctx, `
		INSERT INTO audit_logs (user_id, action_type, entity_name, entity_id, new_values, created_at)
		VALUES ($1, $2, $3, $4, $5, NOW())
	`, userID, action, entity, entityID, details)

	if err != nil {
		log.Printf("AUDIT ERROR: failed to log action %s: %v", action, err)
	}
}

func (h *HandlerDriver) CreateBackupHandler(c *gin.Context) {
	// 1. Проверка прав (только админ)
	role, exists := c.Get("role")
	if !exists || role != "admin" {
		c.JSON(403, gin.H{"error": "Access denied"})
		return
	}

	// 2. Запуск бэкапа
	filename, err := backup.PerformBackup()
	if err != nil {
		// Логируем ошибку в консоль сервера
		log.Printf("Backup handler error: %v", err)
		// Отдаем ошибку клиенту
		c.JSON(500, gin.H{"error": "Backup failed", "details": err.Error()})
		return
	}

	// 3. Логируем действие в аудит (опционально, если есть функция logAction)
	// userId, _ := c.Get("userId")
	// go logAction(context.Background(), db, userId.(int64), "BACKUP_DB", "system", 0, map[string]string{"file": filename})

	// 4. Успешный ответ
	c.JSON(200, gin.H{
		"message": "Backup created successfully",
		"file":    filename,
	})
}

func (h *HandlerDriver) GetMyLoansHandler(c *gin.Context) {
	userId, _ := c.Get("userId")

	query := `
		SELECT lc.id, lc.contract_number, lc.amount, lc.status, lc.start_date,
		       lc.balance,
		       cp.name as product_name
		FROM loan_contracts lc
		JOIN clients c ON lc.client_id = c.id
		JOIN credit_products cp ON lc.product_id = cp.id
		WHERE c.user_id = $1
		ORDER BY lc.created_at DESC
	`
	rows, err := h.db.Query(c.Request.Context(), query, userId)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	// Используем ту же структуру LoanContract, но без лишних полей
	var loans []gin.H
	for rows.Next() {
		var id int64
		var num, status, prodName string
		var amount, balance float64
		var date time.Time
		rows.Scan(&id, &num, &amount, &status, &date, &balance, &prodName)

		loans = append(loans, gin.H{
			"id": id, "contractNumber": num, "amount": amount,
			"status": status, "startDate": date, "productName": prodName,
			"balance": balance,
		})
	}

	if loans == nil {
		loans = []gin.H{}
	}
	c.JSON(200, loans)
}

func (h *HandlerDriver) MakePaymentHandler(c *gin.Context) {
	var req models.PaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверный запрос"})
		return
	}

	userID, _ := c.Get("userId")
	ctx := c.Request.Context()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx error"})
		return
	}
	defer tx.Rollback(ctx)

	// 1. Проверяем, существует ли платеж, не оплачен ли он, и принадлежит ли он этому пользователю
	var paymentAmount, principalAmount float64
	var contractID int64
	var isPaid bool

	// Сложный JOIN, чтобы убедиться, что клиент платит именно за СВОЙ кредит
	err = tx.QueryRow(ctx, `
		SELECT rs.payment_amount, rs.principal_amount, rs.contract_id, rs.is_paid
		FROM repayment_schedule rs
		JOIN loan_contracts lc ON rs.contract_id = lc.id
		JOIN clients cl ON lc.client_id = cl.id
		WHERE rs.id = $1 AND cl.user_id = $2
	`, req.ScheduleID, userID).Scan(&paymentAmount, &principalAmount, &contractID, &isPaid)

	if err != nil {
		c.JSON(404, gin.H{"error": "Платеж не найден или доступ запрещен"})
		return
	}

	if isPaid {
		c.JSON(400, gin.H{"error": "Этот платеж уже оплачен"})
		return
	}

	// 2. Отмечаем платеж как оплаченный
	_, err = tx.Exec(ctx, `UPDATE repayment_schedule SET is_paid = true, paid_at = NOW() WHERE id = $1`, req.ScheduleID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to update schedule"})
		return
	}

	// 3. Уменьшаем баланс (остаток долга) в контракте
	// Важно: баланс уменьшаем на сумму основного долга (principal), либо на полную сумму, зависит от вашей бизнес-логики.
	// Обычно баланс кредита - это "тело". Проценты - это доход банка.
	// В вашей схеме balance - это, скорее всего, остаток тела.
	_, err = tx.Exec(ctx, `
		UPDATE loan_contracts 
		SET balance = balance - $1 
		WHERE id = $2
	`, principalAmount, contractID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to update contract balance"})
		return
	}

	// 4. Записываем операцию
	// Получаем ID сотрудника (системный или NULL), так как платит клиент, employee_id будет null
	_, err = tx.Exec(ctx, `
		INSERT INTO operations (contract_id, operation_type, amount, description, operation_date)
		VALUES ($1, 'scheduled_payment', $2, 'Платеж клиента через ЛК', NOW())
	`, contractID, paymentAmount)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to log operation"})
		return
	}

	// 5. Проверяем, не закрылся ли кредит (баланс <= 0)
	var newBalance float64
	err = tx.QueryRow(ctx, "SELECT balance FROM loan_contracts WHERE id = $1", contractID).Scan(&newBalance)
	if err == nil && newBalance <= 1.0 { // Допускаем погрешность в рубль
		_, _ = tx.Exec(ctx, "UPDATE loan_contracts SET status = 'closed', closed_at = NOW() WHERE id = $1", contractID)
	}

	// 6. Аудит
	LogAction(ctx, tx, userID.(int64), "PAYMENT", "repayment_schedule", req.ScheduleID, map[string]string{
		"amount": fmt.Sprintf("%.2f", paymentAmount),
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(200, gin.H{"message": "Payment successful"})
}

func (h *HandlerDriver) EarlyRepaymentHandler(c *gin.Context) {
	var req models.EarlyRepaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверный запрос"})
		return
	}

	userID, _ := c.Get("userId")
	ctx := c.Request.Context()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx error"})
		return
	}
	defer tx.Rollback(ctx)

	// 1. Получаем текущий баланс и проверяем владельца
	var currentBalance float64
	var status string
	var contractNumber string

	err = tx.QueryRow(ctx, `
		SELECT lc.balance, lc.status, lc.contract_number
		FROM loan_contracts lc
		JOIN clients cl ON lc.client_id = cl.id
		WHERE lc.id = $1 AND cl.user_id = $2
	`, req.ContractID, userID).Scan(&currentBalance, &status, &contractNumber)

	if err != nil {
		c.JSON(404, gin.H{"error": "Договор не найден или доступ запрещен"})
		return
	}

	if status == "closed" {
		c.JSON(400, gin.H{"error": "Кредит уже закрыт"})
		return
	}

	if currentBalance <= 0 {
		c.JSON(400, gin.H{"error": "Задолженность отсутствует"})
		return
	}

	// 2. Закрываем договор
	_, err = tx.Exec(ctx, `
		UPDATE loan_contracts 
		SET balance = 0, status = 'closed', closed_at = NOW() 
		WHERE id = $1
	`, req.ContractID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to close contract"})
		return
	}

	// 3. Удаляем будущие неоплаченные платежи из графика
	// (Так как кредит погашен досрочно, будущие проценты аннулируются)
	_, err = tx.Exec(ctx, `DELETE FROM repayment_schedule WHERE contract_id = $1 AND is_paid = false`, req.ContractID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to clear schedule"})
		return
	}

	// 4. Записываем операцию
	_, err = tx.Exec(ctx, `
		INSERT INTO operations (contract_id, operation_type, amount, description, operation_date)
		VALUES ($1, 'early_repayment', $2, 'Полное досрочное погашение', NOW())
	`, req.ContractID, currentBalance)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to log operation"})
		return
	}

	// 5. Аудит
	LogAction(ctx, tx, userID.(int64), "EARLY_REPAYMENT", "loan_contracts", req.ContractID, map[string]string{
		"amount":   fmt.Sprintf("%.2f", currentBalance),
		"contract": contractNumber,
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(200, gin.H{"message": "Кредит успешно погашен досрочно!", "paidAmount": currentBalance})
}

func (h *HandlerDriver) GetLoanOperationsHandler(c *gin.Context) {
	contractID := c.Param("id")

	// Простейший запрос
	query := `
		SELECT operation_type, amount, operation_date, description
		FROM operations
		WHERE contract_id = $1
		ORDER BY operation_date DESC
	`

	rows, err := h.db.Query(c.Request.Context(), query, contractID)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var ops []gin.H
	for rows.Next() {
		var opType, desc string
		var amount float64
		var date time.Time

		rows.Scan(&opType, &amount, &date, &desc)

		ops = append(ops, gin.H{
			"type":   opType,
			"amount": amount,
			"date":   date,
			"desc":   desc,
		})
	}

	if ops == nil {
		ops = []gin.H{}
	}
	c.JSON(200, ops)
}

func (h *HandlerDriver) GetStatsHandler(c *gin.Context) {
	ctx := c.Request.Context()

	var totalIssued float64
	err := h.db.QueryRow(ctx, "SELECT COALESCE(SUM(amount), 0) FROM loan_contracts WHERE status != 'draft'").Scan(&totalIssued)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error calculating issued stats"})
		return
	}

	var totalRepaid float64
	err = h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount), 0) 
		FROM operations 
		WHERE operation_type IN ('scheduled_payment', 'early_repayment')
	`).Scan(&totalRepaid)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error calculating repaid stats"})
		return
	}

	rows, err := h.db.Query(ctx, `
		SELECT cp.name, COUNT(lc.id)
		FROM loan_contracts lc
		JOIN credit_products cp ON lc.product_id = cp.id
		GROUP BY cp.name
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error calculating pie stats"})
		return
	}
	defer rows.Close()

	type ChartData struct {
		Label string `json:"label"`
		Value int    `json:"value"`
	}
	var distribution []ChartData

	for rows.Next() {
		var name string
		var count int
		rows.Scan(&name, &count)
		distribution = append(distribution, ChartData{Label: name, Value: count})
	}

	c.JSON(200, gin.H{
		"totalIssued":  totalIssued,
		"totalRepaid":  totalRepaid,
		"distribution": distribution,
	})
}