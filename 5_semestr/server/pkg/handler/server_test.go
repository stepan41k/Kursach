package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stepan41k/Kursach/5_semestr/pkg/lib/password"
	"github.com/stepan41k/Kursach/5_semestr/pkg/models"
)

func TestRegisterHandlerValidation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.Default()
	
	r.POST("/register", func(c *gin.Context) {
		var req models.RegisterRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": err.Error()})
			return
		}
		c.Status(200)
	})

	reqBody := []byte(`{}`)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Errorf("Expected 400 for empty JSON, got %d", w.Code)
	}

	reqBody = []byte(`{
		"login": "user1", 
		"password": "password123", 
		"firstName": "Test", 
		"lastName": "User", 
		"email": "bad-email"
	}`)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/register", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != 400 {
		t.Errorf("Expected 400 for bad email, got %d", w.Code)
	}
}

func TestHashLogic(t *testing.T) {
	pwd := "securePass123"
	hash, _ := password.HashPassword(pwd)

	if hash == pwd {
		t.Error("Hash should not match plain text")
	}

	if !password.CheckPasswordHash(pwd, hash) {
		t.Error("Hash verification failed")
	}
}