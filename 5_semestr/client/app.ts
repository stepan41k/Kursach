// --- 1. CONFIG ---
const API_URL = 'http://localhost:3020/api'

interface Window {
	handleLogin: () => Promise<void>
	router: (route: string) => void
	logout: () => void

	// Клиенты
	showAddClientForm: () => void
	submitNewClient: () => Promise<void>

	// Кредиты
	openNewLoanModal: (clientId: number) => Promise<void>
	issueLoan: () => Promise<void>
	previewSchedule: () => void
	showSchedule: (contractId: number) => Promise<void>

	// Сотрудники (Админка)
	showAddEmployeeForm: () => void
	submitNewEmployee: () => Promise<void>
}

// --- 2. INTERFACES ---

interface User {
	id: number
	role: string
	name: string
}
interface Client {
	id: number
	firstName: string
	lastName: string
	middleName?: string
	passportSeries: string
	passportNumber: string
	passportIssuedBy?: string
	dateOfBirth: string
	address: string
	phone: string
	email?: string
}
interface Employee {
	id: number
	firstName: string
	lastName: string
	position: string
	login: string
	role: string
}
interface CreditProduct {
	id: number
	name: string
	minAmount: number
	maxAmount: number
	minTerm: number
	maxTerm: number
	rate: number
	isActive: boolean
}
interface LoanContract {
	id: number
	contractNumber: string
	clientId: number
	clientName: string
	productName: string
	amount: number
	interestRate: number
	termMonths: number
	startDate: string
	status: string
}

// --- 3. API SERVICE ---

class ApiService {
	private async request(endpoint: string, method: string = 'GET', body?: any) {
		try {
			const opts: RequestInit = {
				method,
				headers: { 'Content-Type': 'application/json' },
			}
			if (body) opts.body = JSON.stringify(body)

			const res = await fetch(`${API_URL}${endpoint}`, opts)
			if (!res.ok) {
				const err = await res.json().catch(() => ({ error: res.statusText }))
				throw new Error(err.error || res.statusText)
			}
			return await res.json()
		} catch (e: any) {
			console.error(e)
			alert(`Ошибка: ${e.message}`)
			return null
		}
	}

	async login(l: string, p: string) {
		return this.request('/login', 'POST', { login: l, password: p })
	}

	// Используем существующий эндпоинт регистрации для создания сотрудников админом
	async createEmployee(d: any) {
		return this.request('/register', 'POST', d)
	}
	async getEmployees() {
		return this.request('/employees') || []
	}

	async getClients() {
		return this.request('/clients') || []
	}
	async createClient(c: any) {
		return this.request('/clients', 'POST', c)
	}

	async getProducts() {
		return this.request('/products') || []
	}
	async getLoans() {
		return this.request('/loans') || []
	}
	async issueLoan(d: any) {
		return this.request('/loans', 'POST', d)
	}
	async getSchedule(id: number) {
		return this.request(`/loans/${id}/schedule`) || []
	}

	calculatePreview(amount: number, rate: number, months: number) {
		const monthlyRate = rate / 12 / 100
		const annuity =
			(amount * (monthlyRate * Math.pow(1 + monthlyRate, months))) /
			(Math.pow(1 + monthlyRate, months) - 1)
		return { monthlyPayment: annuity, totalInterest: annuity * months - amount }
	}
}

// --- 4. APP STATE ---

const api = new ApiService()
const app = document.getElementById('app')!
let currentUser: User | null = null
let loadedProducts: CreditProduct[] = []
let currentLoanClientId: number | null = null

// --- 5. VIEWS ---

function renderLogin() {
	// Убрана кнопка регистрации
	app.innerHTML = `
        <div class="login-wrapper">
            <div class="card login-card">
                <div class="brand" style="justify-content: center;"><i class="fas fa-university"></i> RoseBank</div>
                <h2>Вход в систему</h2>
                <div class="form-group"><input type="text" id="loginInput" placeholder="Логин"></div>
                <div class="form-group"><input type="password" id="passwordInput" placeholder="Пароль"></div>
                <button class="btn btn-primary" style="width: 100%" onclick="window.handleLogin()">Войти</button>
                <p style="margin-top: 20px; font-size: 0.8rem; color: #888;">Доступ только для сотрудников банка</p>
            </div>
        </div>`
}

function renderLayout(content: string, activeTab: string) {
	if (!currentUser) return renderLogin()

	// Проверка прав администратора
	const isAdmin = currentUser.role === 'admin'

	app.innerHTML = `
        <div class="app-container">
            <div class="sidebar">
                <div class="brand"><i class="fas fa-spa"></i> RoseBank</div>
                <nav>
                    <div class="nav-item ${
											activeTab === 'dashboard' ? 'active' : ''
										}" onclick="window.router('dashboard')">
                        <i class="fas fa-home"></i> Главная
                    </div>
                    <div class="nav-item ${
											activeTab === 'clients' ? 'active' : ''
										}" onclick="window.router('clients')">
                        <i class="fas fa-users"></i> Клиенты
                    </div>
                    <div class="nav-item ${
											activeTab === 'loans' ? 'active' : ''
										}" onclick="window.router('loans')">
                        <i class="fas fa-file-invoice-dollar"></i> Кредиты
                    </div>
                    
                    ${
											isAdmin
												? `
                    <div style="margin: 10px 0; border-top: 1px solid #eee;"></div>
                    <div class="nav-item ${
											activeTab === 'employees' ? 'active' : ''
										}" onclick="window.router('employees')">
                        <i class="fas fa-user-shield"></i> Сотрудники
                    </div>
                    `
												: ''
										}
                </nav>
                <div style="margin-top: auto;">
                    <div class="nav-item" onclick="window.logout()"><i class="fas fa-sign-out-alt"></i> Выход</div>
                </div>
            </div>
            <div class="main-content">
                <div class="header">
                    <h2>${getPageTitle(activeTab)}</h2>
                    <div class="user-profile">
                        <span>${currentUser.name} (${currentUser.role})</span>
                        <div class="avatar" style="background: ${
													isAdmin ? 'var(--accent-rose)' : 'var(--primary-pink)'
												}; color: #fff;">
                            ${currentUser.name[0]}
                        </div>
                    </div>
                </div>
                <div id="page-content">${content}</div>
            </div>
        </div>`
}

// --- 6. HANDLERS ---

window.handleLogin = async () => {
	const l = (document.getElementById('loginInput') as HTMLInputElement).value
	const p = (document.getElementById('passwordInput') as HTMLInputElement).value
	const res = await api.login(l, p)
	if (res && res.user) {
		currentUser = res.user
		window.router('dashboard')
	}
}

window.logout = () => {
	currentUser = null
	renderLogin()
}

window.router = async (route: string) => {
	renderLayout('<div class="card">Загрузка данных...</div>', route)
	const contentBox = document.getElementById('page-content')
	if (!contentBox) return

	let html = ''

	if (route === 'dashboard') {
		html = `
        <div class="card">
            <h3>Добро пожаловать, ${currentUser!.name}!</h3>
            <p>Вы вошли как: <b>${currentUser!.role}</b></p>
            <p>Используйте меню слева для навигации.</p>
        </div>`
	} else if (route === 'clients') {
		const clients = await api.getClients()
		if (clients && clients.length > 0) {
			const rows = clients
				.map(
					(c: Client) => `
                <tr>
                    <td>${c.lastName} ${c.firstName}</td>
                    <td>${c.passportSeries} ${c.passportNumber}</td>
                    <td>${c.phone}</td>
                    <td><button class="btn btn-secondary" onclick="window.openNewLoanModal(${c.id})">Выдать кредит</button></td>
                </tr>`
				)
				.join('')
			html = `
                <div class="card">
                    <div style="display:flex; justify-content:space-between; margin-bottom:20px">
                        <h3>Список клиентов</h3>
                        <button class="btn btn-primary" onclick="window.showAddClientForm()">+ Новый клиент</button>
                    </div>
                    <table><thead><tr><th>ФИО</th><th>Паспорт</th><th>Телефон</th><th>Действия</th></tr></thead><tbody>${rows}</tbody></table>
                </div>`
		} else {
			html = `<div class="card" style="text-align:center; padding:40px;">
                <h3>Клиентов пока нет</h3>
                <button class="btn btn-primary" onclick="window.showAddClientForm()">+ Создать клиента</button>
            </div>`
		}
	} else if (route === 'loans') {
		const loans = await api.getLoans()
		if (loans && loans.length > 0) {
			const rows = loans
				.map(
					(l: LoanContract) => `
                <tr>
                    <td>${l.contractNumber}</td>
                    <td>${l.clientName}</td>
                    <td>${l.productName}</td>
                    <td>${l.amount.toLocaleString()} ₽</td>
                    <td><span class="status-badge status-active">${
											l.status
										}</span></td>
                    <td><button class="btn btn-secondary" onclick="window.showSchedule(${
											l.id
										})">График</button></td>
                </tr>`
				)
				.join('')
			html = `<div class="card"><h3>Активные кредиты</h3><table><thead><tr><th>Номер</th><th>Клиент</th><th>Продукт</th><th>Сумма</th><th>Статус</th><th>Инфо</th></tr></thead><tbody>${rows}</tbody></table></div>`
		} else {
			html = `<div class="card"><h3>Кредитов нет</h3><p>Перейдите в раздел "Клиенты", чтобы выдать кредит.</p></div>`
		}
	} else if (route === 'employees') {
		// Доступ только для админа
		if (currentUser!.role !== 'admin') {
			html = `<div class="card">Доступ запрещен</div>`
		} else {
			const emps = await api.getEmployees()
			const rows = emps
				.map(
					(e: Employee) => `
                <tr>
                    <td>${e.lastName} ${e.firstName}</td>
                    <td>${e.login}</td>
                    <td>${e.position}</td>
                    <td><span class="status-badge ${
											e.role === 'admin' ? 'status-closed' : 'status-active'
										}">${e.role}</span></td>
                </tr>
            `
				)
				.join('')
			html = `
                <div class="card">
                    <div style="display:flex; justify-content:space-between; margin-bottom:20px">
                        <h3>Управление персоналом</h3>
                        <button class="btn btn-primary" onclick="window.showAddEmployeeForm()">+ Добавить сотрудника</button>
                    </div>
                    <table><thead><tr><th>Имя</th><th>Логин</th><th>Должность</th><th>Роль</th></tr></thead><tbody>${rows}</tbody></table>
                </div>
            `
		}
	}
	contentBox.innerHTML = html
}

// --- ADMIN: EMPLOYEE FORM ---

window.showAddEmployeeForm = () => {
	document.getElementById('page-content')!.innerHTML = `
        <div class="card" style="max-width: 500px; margin: 0 auto;">
            <h3>Новый сотрудник</h3>
            <div class="form-group"><label>Логин для входа</label><input id="newEmpLogin"></div>
            <div class="form-group"><label>Пароль</label><input type="password" id="newEmpPass"></div>
            <div class="form-group"><label>Имя</label><input id="newEmpName"></div>
            <div class="form-group"><label>Фамилия</label><input id="newEmpSurname"></div>
            <div class="form-group"><label>Должность</label><input id="newEmpPos" value="Менеджер"></div>
            <div class="form-group">
                <small style="color:#666">Роль по умолчанию: <b>manager</b>. Созданный сотрудник сможет выдавать кредиты.</small>
            </div>
            <button class="btn btn-primary" onclick="window.submitNewEmployee()">Создать</button>
            <button class="btn btn-secondary" onclick="window.router('employees')">Отмена</button>
        </div>
    `
}

window.submitNewEmployee = async () => {
	const data = {
		login: (document.getElementById('newEmpLogin') as HTMLInputElement).value,
		password: (document.getElementById('newEmpPass') as HTMLInputElement).value,
		firstName: (document.getElementById('newEmpName') as HTMLInputElement)
			.value,
		lastName: (document.getElementById('newEmpSurname') as HTMLInputElement)
			.value,
		position: (document.getElementById('newEmpPos') as HTMLInputElement).value,
	}

	if (!data.login || !data.password) {
		alert('Логин и пароль обязательны')
		return
	}

	if (await api.createEmployee(data)) {
		alert('Сотрудник успешно создан!')
		window.router('employees')
	}
}

// --- CLIENT FORM ---

window.showAddClientForm = () => {
	document.getElementById('page-content')!.innerHTML = `
        <div class="card" style="max-width: 800px;">
            <h3>Новый клиент</h3>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                <div class="form-group"><label>Фамилия</label><input id="ln"></div>
                <div class="form-group"><label>Имя</label><input id="fn"></div>
                <div class="form-group"><label>Отчество</label><input id="mn"></div>
                <div class="form-group"><label>Телефон</label><input id="ph"></div>
                <div class="form-group"><label>Серия пасп.</label><input id="ps"></div>
                <div class="form-group"><label>Номер пасп.</label><input id="pn"></div>
                <div class="form-group"><label>Дата рождения</label><input type="date" id="dob"></div>
                <div class="form-group"><label>Кем выдан</label><input id="pi"></div>
            </div>
            <div class="form-group"><label>Адрес</label><input id="addr"></div>
            <button class="btn btn-primary" onclick="window.submitNewClient()">Сохранить</button>
            <button class="btn btn-secondary" onclick="window.router('clients')">Отмена</button>
        </div>`
}

window.submitNewClient = async () => {
	const data = {
		firstName: (document.getElementById('fn') as HTMLInputElement).value,
		lastName: (document.getElementById('ln') as HTMLInputElement).value,
		middleName: (document.getElementById('mn') as HTMLInputElement).value,
		phone: (document.getElementById('ph') as HTMLInputElement).value,
		passportSeries: (document.getElementById('ps') as HTMLInputElement).value,
		passportNumber: (document.getElementById('pn') as HTMLInputElement).value,
		passportIssuedBy: (document.getElementById('pi') as HTMLInputElement).value,
		dateOfBirth: (document.getElementById('dob') as HTMLInputElement).value,
		address: (document.getElementById('addr') as HTMLInputElement).value,
	}
	if (await api.createClient(data)) {
		alert('Клиент создан')
		window.router('clients')
	}
}

// --- LOAN FORM ---

window.openNewLoanModal = async (clientId: number) => {
	currentLoanClientId = clientId
	loadedProducts = await api.getProducts()
	if (loadedProducts.length === 0) {
		alert('Нет активных кредитных продуктов в базе!')
		return
	}

	const options = loadedProducts
		.map(p => `<option value="${p.id}">${p.name} (${p.rate}%)</option>`)
		.join('')

	document.getElementById('page-content')!.innerHTML = `
        <div class="card" style="max-width: 600px;">
            <h3>Выдача кредита</h3>
            <div class="form-group"><label>Продукт</label><select id="loanProduct" onchange="window.previewSchedule()">${options}</select></div>
            <div class="form-group"><label>Сумма</label><input type="number" id="loanAmount" value="100000"></div>
            <div class="form-group"><label>Срок (мес)</label><input type="number" id="loanTerm" value="12"></div>
            <div id="previewBox" style="background:#f9f9f9; padding:15px; margin:15px 0; border-radius:8px">Расчет...</div>
            <button class="btn btn-primary" onclick="window.issueLoan()">Оформить</button>
            <button class="btn btn-secondary" onclick="window.router('clients')">Отмена</button>
        </div>`
	window.previewSchedule()
}

window.previewSchedule = () => {
	const prodId = Number(
		(document.getElementById('loanProduct') as HTMLInputElement).value
	)
	const amount = Number(
		(document.getElementById('loanAmount') as HTMLInputElement).value
	)
	const term = Number(
		(document.getElementById('loanTerm') as HTMLInputElement).value
	)
	const prod = loadedProducts.find(p => p.id === prodId)

	if (prod) {
		const res = api.calculatePreview(amount, prod.rate, term)
		document.getElementById('previewBox')!.innerHTML = `
            <div>Платеж: <b>${res.monthlyPayment.toFixed(2)} ₽/мес</b></div>
            <div>Переплата: <b>${res.totalInterest.toFixed(2)} ₽</b></div>
        `
	}
}

window.issueLoan = async () => {
	if (!currentUser) {
		alert('Ошибка авторизации')
		return
	}
	
	const data = {
		clientId: currentLoanClientId,
		productId: Number(
			(document.getElementById('loanProduct') as HTMLInputElement).value
		),
		amount: Number(
			(document.getElementById('loanAmount') as HTMLInputElement).value
		),
		termMonths: Number(
			(document.getElementById('loanTerm') as HTMLInputElement).value
		),
		employeeId: currentUser.id,
	}
	if (await api.issueLoan(data)) {
		alert('Кредит выдан!')
		window.router('loans')
	}
}

window.showSchedule = async (id: number) => {
	const s = await api.getSchedule(id)
	const rows = s
		.map(
			(r: any) =>
				`<tr><td>${new Date(r.paymentDate).toLocaleDateString()}</td><td>${
					r.paymentAmount
				}</td><td>${r.remainingBalance}</td><td>${
					r.isPaid ? 'Да' : 'Нет'
				}</td></tr>`
		)
		.join('')
	document.getElementById(
		'page-content'
	)!.innerHTML = `<div class="card"><h3>График</h3><button class="btn btn-secondary" onclick="window.router('loans')">Назад</button><table><thead><tr><th>Дата</th><th>Сумма</th><th>Остаток</th><th>Статус</th></tr></thead><tbody>${rows}</tbody></table></div>`
}

function getPageTitle(t: string) {
	const m: any = {
		dashboard: 'Обзор',
		clients: 'Управление клиентами',
		loans: 'Портфель',
		employees: 'Сотрудники',
	}
	return m[t] || ''
}

// Init
renderLogin()
