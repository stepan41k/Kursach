package handler

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/auth"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/backup"
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
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx error"})
		return
	}
	defer tx.Rollback(ctx)

	var newUserID int64

	err = tx.QueryRow(ctx, "CALL sp_register_employee($1, $2, $3, $4, $5, $6, NULL)",
		req.Login,
		req.Password,
		req.FirstName,
		req.LastName,
		req.Position,
		req.Email,
	).Scan(&newUserID)

	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	adminID, _ := c.Get("userId")

	LogAction(ctx, tx, adminID.(int64), "REGISTER_EMPLOYEE", "employees", newUserID, map[string]string{
		"role":  req.Position,
		"login": req.Login,
		"name":  fmt.Sprintf("%s %s", req.FirstName, req.LastName),
		"email": req.Email,
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(201, gin.H{"message": "Сотрудник успешно зарегистрирован"})
}

func (h *HandlerDriver) LoginHandler(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Логин и пароль обязательны"})
		return
	}

	var userID int64
	var pwdHash, roleName string
	var fName, lName, email *string

	err := h.db.QueryRow(c.Request.Context(), "SELECT * FROM fn_get_user_by_login($1)", req.Login).
		Scan(&userID, &pwdHash, &roleName, &fName, &lName, &email)

	if err != nil {
		c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
		return
	}

	if req.Password != pwdHash {
		c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
		return
	}

	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &auth.Claims{
		UserID:           userID,
		Role:             roleName,
		RegisteredClaims: jwt.RegisteredClaims{ExpiresAt: jwt.NewNumericDate(expirationTime)},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString(auth.JWTKey)

	fullName := "Пользователь"
	if fName != nil && lName != nil {
		fullName = fmt.Sprintf("%s %s", *fName, *lName)
	}

	if email != nil && *email != "" {
		go mail.SendLoginEmail(*email, fullName, c.ClientIP())
	}

	c.JSON(200, models.LoginResponse{
		Token: tokenString,
		User: struct {
			ID       int64  `json:"id"`
			Role     string `json:"role"`
			FullName string `json:"name"`
		}{userID, roleName, fullName},
	})
}

func (h *HandlerDriver) GetClients(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_all_clients()")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var clients []gin.H
	for rows.Next() {
		var id int64
		var fn, ln, ps, pn, ph, addr string
		var mn, pi, em *string
		var dob, createdAt time.Time

		err := rows.Scan(&id, &fn, &ln, &mn, &ps, &pn, &pi, &dob, &addr, &ph, &em, &createdAt)
		if err != nil {
			log.Println("Scan error:", err)
			continue
		}

		clients = append(clients, gin.H{
			"id": id, "firstName": fn, "lastName": ln, "middleName": mn,
			"passportSeries": ps, "passportNumber": pn, "passportIssuedBy": pi,
			"dateOfBirth": dob.Format("2006-01-02"),
			"address":     addr, "phone": ph, "email": em,
			"createdAt": createdAt,
		})
	}

	if clients == nil {
		clients = []gin.H{}
	}
	c.JSON(200, clients)
}

func (h *HandlerDriver) CreateClient(c *gin.Context) {
	var req models.CreateClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Ошибка валидации данных"})
		return
	}

	genLogin := password.GenerateRandomPassword(8)
	genPassword := password.GenerateRandomPassword(8)

	ctx := c.Request.Context()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx fail"})
		return
	}
	defer tx.Rollback(ctx)

	var clientID int64

	err = tx.QueryRow(ctx, `CALL sp_create_client($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NULL)`,
		genLogin, genPassword,
		req.FirstName, req.LastName, req.MiddleName,
		req.PassportSeries, req.PassportNumber, req.PassportIssued,
		req.DateOfBirth, req.Address, req.Phone, req.Email,
	).Scan(&clientID)

	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	opID, _ := c.Get("userId")
	adminID := int64(0)
	if opID != nil {
		adminID = opID.(int64)
	}

	LogAction(ctx, tx, adminID, "CREATE_CLIENT", "clients", clientID, map[string]string{
		"login": genLogin,
		"name":  fmt.Sprintf("%s %s", req.LastName, req.FirstName),
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	go mail.SendClientWelcomeEmail(
		req.Email,
		fmt.Sprintf("%s %s", req.FirstName, req.LastName),
		genLogin,
		genPassword,
	)

	c.JSON(201, gin.H{"message": "Client created", "id": clientID})
}

func (h *HandlerDriver) GetProducts(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_active_products()")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var products []gin.H
	for rows.Next() {
		var id, minTerm, maxTerm int
		var name string
		var minAmt, maxAmt int64
		var rate float64
		var isActive bool

		err := rows.Scan(&id, &name, &minAmt, &maxAmt, &minTerm, &maxTerm, &rate, &isActive)
		if err != nil {
			continue
		}

		products = append(products, gin.H{
			"id": id, "name": name,
			"minAmount": float64(minAmt) / 100.0,
			"maxAmount": float64(maxAmt) / 100.0,
			"minTerm":   minTerm, "maxTerm": maxTerm,
			"rate": rate, "isActive": isActive,
		})
	}

	if products == nil {
		products = []gin.H{}
	}
	c.JSON(200, products)
}

func (h *HandlerDriver) IssueLoan(c *gin.Context) {
	var req models.IssueLoanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid JSON"})
		return
	}
	ctx := c.Request.Context()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Tx begin failed"})
		return
	}
	defer tx.Rollback(ctx)

	var newContractID int64
	amountKopecks := int64(req.Amount * 100)

	err = tx.QueryRow(ctx, "CALL sp_issue_loan($1, $2, $3, $4, $5, NULL)",
		req.ClientID,
		req.ProductID,
		amountKopecks,
		req.TermMonths,
		req.EmployeeID,
	).Scan(&newContractID)

	if err != nil {
		log.Printf("Procedure call failed: %v", err)
		c.JSON(500, gin.H{"error": "Failed to issue loan (DB Procedure Error)"})
		return
	}

	LogAction(ctx, tx, req.EmployeeID, "TOOK_LOAN", "loan_contracts", newContractID, map[string]string{
		"amount": fmt.Sprintf("%.2f", req.Amount),
		"type":   "via_stored_procedure",
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(201, gin.H{"message": "Loan issued", "contractId": newContractID})
}

func (h *HandlerDriver) GetLoans(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_all_loans()")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var loans []gin.H
	for rows.Next() {
		var id int64
		var contractNum, status, clientName, prodName string
		var amount, balance int64
		var rate float64
		var startDate time.Time
		var term int

		err := rows.Scan(&id, &contractNum, &amount, &status, &startDate, &rate, &term, &balance, &clientName, &prodName)
		if err != nil {
			continue
		}

		loans = append(loans, gin.H{
			"id":             id,
			"contractNumber": contractNum,
			"amount":         float64(amount) / 100.0,
			"status":         status,
			"startDate":      startDate,
			"clientName":     clientName,
			"productName":    prodName,
			"interestRate":   rate,
			"termMonths":     term,
			"balance":        float64(balance) / 100.0,
		})
	}

	if loans == nil {
		loans = []gin.H{}
	}
	c.JSON(200, loans)
}

func (h *HandlerDriver) GetSchedule(c *gin.Context) {
	contractID := c.Param("id")

	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_repayment_schedule($1)", contractID)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var schedule []gin.H
	for rows.Next() {
		var id int64
		var paymentDate time.Time
		var paymentAmount, principal, interest, balance int64
		var isPaid bool

		if err := rows.Scan(&id, &paymentDate, &paymentAmount, &principal, &interest, &balance, &isPaid); err != nil {
			continue
		}

		schedule = append(schedule, gin.H{
			"id":               id,
			"paymentDate":      paymentDate,
			"paymentAmount":    float64(paymentAmount) / 100.0,
			"principal":        float64(principal) / 100.0,
			"interest":         float64(interest) / 100.0,
			"remainingBalance": float64(balance) / 100.0,
			"isPaid":           isPaid,
		})
	}

	if schedule == nil {
		schedule = []gin.H{}
	}
	c.JSON(200, schedule)
}

func (h *HandlerDriver) GetEmployeesHandler(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_all_employees()")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var employees []gin.H
	for rows.Next() {
		var id int64
		var fn, ln, pos, login, role string
		if err := rows.Scan(&id, &fn, &ln, &pos, &login, &role); err != nil {
			log.Println("Scan error:", err)
			continue
		}
		employees = append(employees, gin.H{
			"id": id, "firstName": fn, "lastName": ln,
			"position": pos, "login": login, "role": role,
		})
	}

	if employees == nil {
		employees = []gin.H{}
	}
	c.JSON(200, employees)
}

func (h *HandlerDriver) GetLogsHandler(c *gin.Context) {
	action := c.Query("action")
	fromDate := c.Query("from")

	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_audit_logs($1, $2)", action, fromDate)
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
		var login, fn, ln *string

		err := rows.Scan(&id, &act, &ent, &entID, &ts, &details, &login, &fn, &ln)
		if err != nil {
			log.Printf("Scan error: %v", err)
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
			"id":       id,
			"action":   act,
			"entity":   ent,
			"entityId": entID,
			"date":     ts,
			"details":  details,
			"user":     userName,
		})
	}

	if logs == nil {
		logs = []gin.H{}
	}
	c.JSON(200, logs)
}

func (h *HandlerDriver) CreateBackupHandler(c *gin.Context) {
	role, exists := c.Get("role")
	if !exists || role != "admin" {
		c.JSON(403, gin.H{"error": "Access denied"})
		return
	}

	ctx := c.Request.Context()

	filename, err := backup.PerformBackup()
	if err != nil {
		log.Printf("Backup handler error: %v", err)
		c.JSON(500, gin.H{"error": "Backup failed", "details": err.Error()})
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		log.Printf("Failed to create transaction in log creating: %v", err)
		c.JSON(500, gin.H{"error": "Backup failed", "details": err.Error()})
	}

	userId, _ := c.Get("userId")
	LogAction(context.Background(), tx, userId.(int64), "BACKUP_DB", "system", 0, map[string]string{"file": filename})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(200, gin.H{
		"message": "Backup created successfully",
		"file":    filename,
	})
}

func (h *HandlerDriver) GetMyLoansHandler(c *gin.Context) {
	userID, _ := c.Get("userId")

	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_client_loans($1)", userID)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var loans []gin.H
	for rows.Next() {
		var id int64
		var num, status, prodName string
		var amount, balance int64
		var date time.Time
		var paid, total int64

		err := rows.Scan(&id, &num, &amount, &status, &date, &balance, &prodName, &paid, &total)
		if err != nil {
			log.Println("Scan error:", err)
			continue
		}

		loans = append(loans, gin.H{
			"id":             id,
			"contractNumber": num,
			"amount":         float64(amount) / 100.0,
			"status":         status,
			"startDate":      date,
			"productName":    prodName,
			"balance":        float64(balance) / 100.0,
			"progress":       fmt.Sprintf("%d/%d", paid, total),
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

	var contractID int64
	var paymentAmount float64

	err = tx.QueryRow(ctx, `
		SELECT rs.contract_id, rs.payment_amount
		FROM repayment_schedule rs
		JOIN loan_contracts lc ON rs.contract_id = lc.id
		JOIN clients cl ON lc.client_id = cl.id
		WHERE rs.id = $1 AND cl.user_id = $2
	`, req.ScheduleID, userID).Scan(&contractID, &paymentAmount)

	if err != nil {
		c.JSON(403, gin.H{"error": "Платеж не найден или доступ запрещен"})
		return
	}

	_, err = tx.Exec(ctx, "CALL sp_make_payment($1)", req.ScheduleID)

	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	LogAction(ctx, tx, userID.(int64), "PAYMENT", "repayment_schedule", req.ScheduleID, map[string]string{
		"amount": fmt.Sprintf("%.2f", paymentAmount),
		"method": "via_stored_procedure",
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
		c.JSON(400, gin.H{"error": "Invalid request"})
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

	var paidAmount int64

	err = tx.QueryRow(ctx, "CALL sp_early_repayment($1, $2, NULL)",
		req.ContractID, userID).Scan(&paidAmount)

	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	LogAction(ctx, tx, userID.(int64), "EARLY_REPAYMENT", "loan_contracts", req.ContractID, map[string]string{
		"amount": fmt.Sprintf("%.2f", float64(paidAmount)/100.0),
		"method": "via_stored_procedure",
	})

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "Commit failed"})
		return
	}

	c.JSON(200, gin.H{
		"message":    "Кредит погашен досрочно",
		"paidAmount": float64(paidAmount) / 100.0,
	})
}

func (h *HandlerDriver) GetLoanOperationsHandler(c *gin.Context) {
	contractID := c.Param("id")

	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_loan_operations($1)", contractID)
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

		if err := rows.Scan(&opType, &amount, &date, &desc); err != nil {
			continue
		}

		ops = append(ops, gin.H{
			"type":   opType,
			"amount": float64(amount) / 100.0,
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
	var jsonStats []byte

	err := h.db.QueryRow(c.Request.Context(), "SELECT fn_get_dashboard_stats()").Scan(&jsonStats)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get stats: " + err.Error()})
		return
	}

	c.Data(200, "application/json", jsonStats)
}

func (h *HandlerDriver) GetFinanceReportHandler(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), "SELECT * FROM fn_get_financial_report()")
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var report []gin.H
	for rows.Next() {
		var month string
		var issued, repaid, net int64
		rows.Scan(&month, &issued, &repaid, &net)

		report = append(report, gin.H{
			"month":  month,
			"issued": float64(issued) / 100.0,
			"repaid": float64(repaid) / 100.0,
			"net":    float64(net) / 100.0,
		})
	}
	if report == nil {
		report = []gin.H{}
	}
	c.JSON(200, report)
}

func LogAction(ctx context.Context, tx pgx.Tx, userID int64, action string, entity string, entityID int64, details map[string]string) {
	_, err := tx.Exec(ctx, "CALL sp_audit_log($1, $2, $3, $4, $5)",
		userID, action, entity, entityID, details)

	if err != nil {
		log.Printf("AUDIT ERROR: %v", err)
	}
}
