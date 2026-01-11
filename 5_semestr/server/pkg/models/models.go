package models

import "time"

type PaymentRequest struct {
	ScheduleID int64 `json:"scheduleId" binding:"required"`
}

type EarlyRepaymentRequest struct {
	ContractID int64 `json:"contractId" binding:"required"`
}

type CreateClientRequest struct {
	FirstName      string `json:"firstName" binding:"required,min=2,max=100"`
	LastName       string `json:"lastName" binding:"required,min=2,max=100"`
	MiddleName     string `json:"middleName"`
	
	PassportSeries string `json:"passportSeries" binding:"required,len=4,numeric"`
	PassportNumber string `json:"passportNumber" binding:"required,len=6,numeric"`
	PassportIssued string `json:"passportIssuedBy"`
	
	DateOfBirth    string `json:"dateOfBirth" binding:"required"` 
	
	Address        string `json:"address"`
	Phone          string `json:"phone" binding:"min=10"`
	Email          string `json:"email" binding:"required,email"`
}

type RegisterRequest struct {
	Login     string `json:"login" binding:"required,min=4,alphanum"`
	Password  string `json:"password" binding:"required,min=6"`
	FirstName string `json:"firstName" binding:"required,min=2"`
	LastName  string `json:"lastName" binding:"required,min=2"`
	Position  string `json:"position"`
	Email     string `json:"email" binding:"required,email"`
}

type LoginRequest struct {
	Login    string `json:"login" binding:"required"` 
	Password string `json:"password" binding:"required"`
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