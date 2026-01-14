const API_URL = 'http://localhost:3020/api'

declare var pdfMake: any
declare var Chart: any;

interface Window {
	handleLogin: () => Promise<void>
	router: (route: string) => void
	logout: () => void

	showAddClientForm: () => void
	submitNewClient: () => Promise<void>

	openNewLoanModal: (clientId: number) => Promise<void>
	issueLoan: () => Promise<void>
	previewSchedule: () => void
	showSchedule: (contractId: number) => Promise<void>

	showAddEmployeeForm: () => void
	submitNewEmployee: () => Promise<void>

	doEarlyRepayment: (contractId: number, balance: number) => void
	applyLogFilters: () => void
	doBackup: () => void
	payInstallment: (
		scheduleId: number,
		amount: number,
		contractId: number
	) => void
}


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
	email: string
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


class ApiService {
	private async request(endpoint: string, method: string = 'GET', body?: any) {
		try {
			const token = localStorage.getItem('authToken')

			const headers: HeadersInit = {
				'Content-Type': 'application/json',
			}

			if (token) {
				headers['Authorization'] = `Bearer ${token}`
			}

			const opts: RequestInit = {
				method,
				headers,
			}

			if (body) opts.body = JSON.stringify(body)

			const res = await fetch(`${API_URL}${endpoint}`, opts)

			if (res.status === 401) {
				window.logout()
				throw new Error('Сессия истекла. Войдите снова.')
			}

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
		try {
			const res = await fetch(`${API_URL}/login`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ login: l, password: p }),
			})

			if (!res.ok) throw new Error('Ошибка входа')

			const data = await res.json()

			if (data.token) {
				localStorage.setItem('authToken', data.token)
			}

			return data
		} catch (e) {
			return null
		}
	}

	async getLoanById(id: number) {
		const loans = await this.getLoans()
		return loans.find((l: any) => l.id === id)
	}
	async makePayment(scheduleId: number) {
		return this.request('/pay', 'POST', { scheduleId })
	}
	async getFinanceReport() {
		return this.request('/finance-report') || []
	}
	async getLoanOperations(contractId: number) {
		return this.request(`/loans/${contractId}/operations`) || []
	}
	async createBackup() {
		return this.request('/backup', 'POST', {})
	}
	async getMyLoans() {
		return this.request('/my-loans') || []
	}
	async register(d: any) {
		return this.request('/register', 'POST', d)
	}
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
	async getStats() {
		return this.request('/stats') || {}
	}
	async repayEarly(contractId: number) {
		return this.request('/repay-early', 'POST', { contractId })
	}
	async issueLoan(d: any) {
		return this.request('/loans', 'POST', d)
	}
	async getSchedule(id: number) {
		return this.request(`/loans/${id}/schedule`) || []
	}
	async getLogs(filters: any = {}) {
		const params = new URLSearchParams(filters).toString()
		return this.request(`/logs?${params}`) || []
	}

	calculatePreview(amountRub: number, rate: number, months: number) {
		const monthlyRate = rate / 12 / 100
		const annuity =
			(amountRub * (monthlyRate * Math.pow(1 + monthlyRate, months))) /
			(Math.pow(1 + monthlyRate, months) - 1)

		return {
			monthlyPayment: annuity,
			totalInterest: annuity * months - amountRub,
		}
	}
}


const api = new ApiService()
const app = document.getElementById('app')!
let currentUser: User | null = null
let loadedProducts: CreditProduct[] = []
let currentLoanClientId: number | null = null
let logsInterval: any = null
let currentLogFilters: any = {}


function renderLogin() {
	app.innerHTML = `
        <div class="login-wrapper">
            <div class="card login-card">
                <div class="brand" style="justify-content: center;">
                    <i class="fas fa-university"></i> RoseBank
                </div>
                <h2>Вход в АИС</h2>
                
                <div class="form-group">
                    <input type="text" id="loginInput" placeholder="Логин">
                </div>
                <div class="form-group">
                    <input type="password" id="passwordInput" placeholder="Пароль">
                </div>
                <div id="loginError" style="color: #e74c3c; font-size: 0.9rem; margin-bottom: 15px; min-height: 20px; font-weight: 500;"></div>

                <button class="btn btn-primary" style="width: 100%" onclick="window.handleLogin()">Войти</button>
            </div>
        </div>`
}

function renderLayout(content: string, activeTab: string) {
	if (!currentUser) return renderLogin()

	const isAdmin = currentUser.role === 'admin'
	const isClient = currentUser.role === 'client'
    const isStaff = currentUser.role === 'admin' || currentUser.role === 'manager';

	app.innerHTML = `
        <div class="app-container">
            <div class="sidebar">
                <div class="brand"><i class="fas fa-spa"></i> RoseBank</div>
                <nav>
                    <!-- ОБЩЕЕ: Главная -->
                    <div class="nav-item ${
											activeTab === 'dashboard' ? 'active' : ''
										}" onclick="window.router('dashboard')">
                        <i class="fas fa-home"></i> Главная
                    </div>

                    <!-- ДЛЯ СОТРУДНИКОВ (Не клиентов) -->
                    ${
											!isClient
												? `
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
                    `
												: ''
										}
                    
                    <!-- ДЛЯ КЛИЕНТОВ -->
                    ${
											isClient
												? `
                    <div class="nav-item ${
											activeTab === 'my-loans' ? 'active' : ''
										}" onclick="window.router('my-loans')">
                        <i class="fas fa-wallet"></i> Мои кредиты
                    </div>
                    `
												: ''
										}
					${
						isStaff
							? `
					<div class="nav-item ${
							activeTab === 'stats' ? 'active' : ''
						}" onclick="window.router('stats')">
						<i class="fas fa-chart-pie"></i> Статистика
					</div>
					`
							: ''
					}

                    <!-- ДЛЯ АДМИНА -->
                    ${
											isAdmin
												? `
                    <div style="margin: 10px 0; border-top: 1px solid #eee;"></div>
                    <div class="nav-item ${
											activeTab === 'employees' ? 'active' : ''
										}" onclick="window.router('employees')">
                        <i class="fas fa-user-shield"></i> Сотрудники
                    </div>
                    <div class="nav-item ${
											activeTab === 'logs' ? 'active' : ''
										}" onclick="window.router('logs')">
                        <i class="fas fa-list-alt"></i> Логи событий
                    </div>
                    <!-- КНОПКА БЭКАПА -->
                    <div class="nav-item" onclick="window.doBackup()" style="color: var(--accent-rose)">
                        <i class="fas fa-database"></i> Бэкап БД
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
                        <span>${currentUser.name || 'Пользователь'} (${
		currentUser.role
	})</span>
                        <div class="avatar">${
													(currentUser.name || 'U')[0]
												}</div>
                    </div>
                </div>
                <div id="page-content">${content}</div>
            </div>
        </div>`
}


window.handleLogin = async () => {
	const loginInput = document.getElementById('loginInput') as HTMLInputElement
	const passInput = document.getElementById('passwordInput') as HTMLInputElement
	const errorBox = document.getElementById('loginError') as HTMLElement

	const l = (document.getElementById('loginInput') as HTMLInputElement).value
	const p = (document.getElementById('passwordInput') as HTMLInputElement).value

	loginInput.style.border = '1px solid #eee'
	passInput.style.border = '1px solid #eee'
	errorBox.innerText = ''

	let errorMsg = ''

	if (!l) {
		loginInput.style.border = '1px solid #e74c3c'
		errorMsg = 'Введите логин'
	} else if (!p) {
		passInput.style.border = '1px solid #e74c3c'
		errorMsg = 'Введите пароль'
	}

	if (errorMsg) {
		errorBox.innerText = errorMsg
		return
	}

	const res = await api.login(l, p)

	if (res && res.user) {
		currentUser = res.user
		localStorage.setItem('userData', JSON.stringify(currentUser))
		window.router('dashboard')
	} else {
		passInput.style.border = '1px solid #e74c3c'
		errorBox.innerText = 'Неверный логин или пароль'
	}
}

window.logout = () => {
	currentUser = null
	localStorage.removeItem('authToken')
	localStorage.removeItem('userData')
	renderLogin()
}

window.router = async (route: string) => {
	if (logsInterval) {
		clearInterval(logsInterval)
		logsInterval = null
	}
	
	renderLayout('<div class="card">Загрузка данных...</div>', route)
	const contentBox = document.getElementById('page-content')
	if (!contentBox) return

	let html = ''

	if (route === 'dashboard') {
		html = `
        <div class="card">
            <!-- Добавили margin-bottom -->
            <h3 style="margin-bottom: 15px;">Добро пожаловать, ${
							currentUser!.name
						}!</h3>
            
            <p style="margin-bottom: 8px;">Вы вошли как: <b>${
							currentUser!.role
						}</b></p>
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
			html = `
            <div class="card" style="text-align:center; padding: 60px 40px;">
                <h3 style="margin-bottom: 25px; color: #333;">Клиентов пока нет</h3>
                <button class="btn btn-primary" onclick="window.showAddClientForm()" style="padding: 12px 24px; font-size: 1rem;">
                    + Создать клиента
                </button>
            </div>`
		}
	} else if (route === 'loans') {
		const loans = await api.getLoans()
		if (loans && loans.length > 0) {
			const rows = loans
				.map((l: any) => {
					// ЛОГИКА ЦВЕТОВ
					let badgeStyle = 'background:#e8f5e9; color:#2e7d32'

					if (l.status === 'closed') {
						badgeStyle = 'background:#ffebee; color:#c62828'
					}

					return `
                <tr>
                    <td>${l.contractNumber}</td>
                    <td>${l.clientName}</td>
                    <td>${l.productName}</td>
                    <td>${formatMoney(l.amount)} ₽</td>
                    <!-- Применяем стиль здесь -->
                    <td><span class="status-badge" style="${badgeStyle}">${
						l.status
					}</span></td>
                    <td><button class="btn btn-secondary" onclick="window.showSchedule(${
											l.id
										})">График</button></td>
                </tr>`
				})
				.join('')

			html = `<div class="card"><h3>Активные кредиты</h3><table><thead><tr><th>Номер</th><th>Клиент</th><th>Продукт</th><th>Сумма</th><th>Статус</th><th>Инфо</th></tr></thead><tbody>${rows}</tbody></table></div>`
		} else {
			html = `
             <div class="card" style="text-align:center; padding: 60px 40px;">
                <h3 style="margin-bottom: 15px;">Кредитов нет</h3>
                <p style="color: #666;">Перейдите в раздел "Клиенты", чтобы выдать кредит.</p>
             </div>`
		}
	} else if (route === 'employees') {
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
	} else if (route === 'logs') {
        if (currentUser!.role !== 'admin') {
            html = `<div class="card">Доступ запрещен</div>`;
        } else {
            currentLogFilters = {};
            
            const logs = await api.getLogs();
            html = renderLogsPage(logs);

            logsInterval = setInterval(() => {
                updateLogsTableOnly();
            }, 5000);
        }
	} else if (route === 'my-loans') {
		const loans = await api.getMyLoans()
		if (loans.length > 0) {
			const rows = loans
				.map((l: any) => {
					let badgeStyle = 'background:#e8f5e9; color:#2e7d32' 

					if (l.status === 'closed') {
						badgeStyle = 'background:#ffebee; color:#c62828' 
					}
					return `
                <tr>
                    <td>${l.contractNumber}</td>
                    <td>
                        ${l.productName}
                        <div style="font-size:0.8em; color:#888">Выплачено: ${
													l.progress || '?'
												} мес.</div>
                    </td>
                    <td>${formatMoney(l.amount)} ₽</td>
                    <td>${new Date(l.startDate).toLocaleDateString()}</td>
                    <!-- Применяем стиль здесь -->
                    <td><span class="status-badge" style="${badgeStyle}">${
						l.status
					}</span></td>
                    <td><button class="btn btn-secondary" onclick="window.showSchedule(${
											l.id
										})">График</button></td>
                </tr>`
				})
				.join('')

			html = `<div class="card"><h3>Мои текущие кредиты</h3><table><thead><tr><th>Номер</th><th>Продукт</th><th>Сумма</th><th>Дата</th><th>Статус</th><th>Действия</th></tr></thead><tbody>${rows}</tbody></table></div>`
		} else {
			html = `
            <div class="card" style="text-align:center; padding: 60px 40px;">
                <h3>У вас пока нет активных кредитов</h3>
            </div>`
		}
	} else if (route === 'stats') {
		if (currentUser!.role === 'client') {
			html = `<div class="card">Доступ запрещен</div>`
		} else {
			const [stats, financeReport] = await Promise.all([
				api.getStats(),
				api.getFinanceReport(),
			])

			html = renderStatsPage(stats, financeReport)

			setTimeout(() => initStatsChart(stats.distribution), 100)
		}
	}

	contentBox.innerHTML = html

	contentBox.innerHTML = html
}


window.showAddEmployeeForm = () => {
	document.getElementById('page-content')!.innerHTML = `
        <div class="card" style="max-width: 500px; margin: 0 auto;">
            <h3>Новый сотрудник</h3>
            
            <div class="form-group">
                <label>Логин *</label>
                <input id="newEmpLogin">
                <small id="err-elogin" class="error-message"></small>
            </div>
            <div class="form-group">
                <label>Пароль *</label>
                <input type="password" id="newEmpPass">
                <small id="err-epass" class="error-message"></small>
            </div>
            
            <div class="form-group">
                <label>Имя *</label>
                <input id="newEmpName">
                <small id="err-ename" class="error-message"></small>
            </div>
            <div class="form-group">
                <label>Фамилия *</label>
                <input id="newEmpSurname">
                <small id="err-esurname" class="error-message"></small>
            </div>
            
            <div class="form-group">
                <label>Email *</label>
                <input type="email" id="newEmpEmail">
                <small id="err-eemail" class="error-message"></small>
            </div>
            
            <div class="form-group">
                <label>Должность</label>
                <select id="newEmpPos" style="padding: 12px;">
                    <option value="Менеджер">Менеджер</option>
                </select>
            </div>
            
            <button class="btn btn-primary" onclick="window.submitNewEmployee()">Создать</button>
            <button class="btn btn-secondary" onclick="window.router('employees')">Отмена</button>
        </div>
    `
}

window.submitNewEmployee = async () => {
	let isValid = true
	isValid =
		validateField(
			'newEmpLogin',
			REGEX.MIN_4,
			'err-elogin',
			'Минимум 4 символа'
		) && isValid
	isValid =
		validateField(
			'newEmpPass',
			REGEX.MIN_6,
			'err-epass',
			'Минимум 6 символов'
		) && isValid
	isValid =
		validateField('newEmpName', REGEX.MIN_2, 'err-ename', 'Заполните поле') &&
		isValid
	isValid =
		validateField(
			'newEmpSurname',
			REGEX.MIN_2,
			'err-esurname',
			'Заполните поле'
		) && isValid
	isValid =
		validateField(
			'newEmpEmail',
			v => REGEX.EMAIL.test(v),
			'err-eemail',
			'Некорректный Email'
		) && isValid

	if (!isValid) return

	const data = {
		login: (document.getElementById('newEmpLogin') as HTMLInputElement).value,
		password: (document.getElementById('newEmpPass') as HTMLInputElement).value,
		firstName: (document.getElementById('newEmpName') as HTMLInputElement)
			.value,
		lastName: (document.getElementById('newEmpSurname') as HTMLInputElement)
			.value,
		position: (document.getElementById('newEmpPos') as HTMLInputElement).value,
		email: (document.getElementById('newEmpEmail') as HTMLInputElement).value,
	}

	if (await api.createEmployee(data)) {
		alert('Сотрудник создан!')
		window.router('employees')
	}
}


window.showAddClientForm = () => {
	document.getElementById('page-content')!.innerHTML = `
        <div class="card" style="max-width: 800px; padding: 30px;">
            <h3 style="margin-bottom: 20px;">Новый клиент</h3>
            
            <div class="alert-info" style="background:#e3f2fd; padding: 10px 15px; border-radius: 8px; margin-bottom: 20px; font-size: 0.9em; color:#0d47a1; border-left: 4px solid #2196f3;">
                <i class="fas fa-info-circle" style="margin-right: 8px;"></i> Логин и пароль будут отправлены на Email.
            </div>

            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 15px;">
                <div class="form-group">
                    <label>Фамилия *</label>
                    <input id="ln">
                    <small id="err-ln" class="error-message"></small>
                </div>
                <div class="form-group">
                    <label>Имя *</label>
                    <input id="fn">
                    <small id="err-fn" class="error-message"></small>
                </div>
                <div class="form-group">
                    <label>Отчество (При наличии)</label>
                    <input id="mn">
                    <small class="error-message"></small>
                </div>
                <div class="form-group">
                    <label>Телефон *</label>
                    <input id="ph">
                    <small id="err-ph" class="error-message"></small>
                </div>
                
                <div class="form-group">
                    <label>Серия паспорта *</label>
                    <input id="ps" maxlength="4">
                    <small id="err-ps" class="error-message"></small>
                </div>
                <div class="form-group">
                    <label>Номер паспорта *</label>
                    <input id="pn" maxlength="6">
                    <small id="err-pn" class="error-message"></small>
                </div>
                
                <div class="form-group">
                    <label>Дата рождения *</label>
                    <input type="date" id="dob">
                    <small id="err-dob" class="error-message"></small>
                </div>
                
                <div class="form-group">
                    <label>Email *</label>
                    <input type="email" id="clEmail" placeholder="mail@example.com">
                    <small id="err-email" class="error-message"></small>
                </div>
            </div>
            
            <div class="form-group" style="margin-bottom: 15px;">
                <label>Кем выдан *</label>
                <input id="pi">
				<small id="err-pi" class="error-message"></small>
            </div>
            <div class="form-group" style="margin-bottom: 25px;">
                <label>Адрес *</label>
                <input id="addr">
				<small id="err-addr" class="error-message"></small>
            </div>
            
            <div style="margin-top: 20px; display: flex; gap: 15px;">
                <button class="btn btn-primary" onclick="window.submitNewClient()" style="padding: 10px 20px;">Зарегистрировать</button>
                <button class="btn btn-secondary" onclick="window.router('clients')" style="padding: 10px 20px;">Отмена</button>
            </div>
        </div>`
}

window.submitNewClient = async () => {
	let isValid = true

	isValid =
		validateField('ln', REGEX.MIN_2, 'err-ln', 'Минимум 2 буквы') && isValid
	isValid =
		validateField('fn', REGEX.MIN_2, 'err-fn', 'Минимум 2 буквы') && isValid
	isValid =
		validateField(
			'ps',
			v => REGEX.PASSPORT_SERIES.test(v),
			'err-ps',
			'Ровно 4 цифры'
		) && isValid
	isValid =
		validateField(
			'pn',
			v => REGEX.PASSPORT_NUMBER.test(v),
			'err-pn',
			'Ровно 6 цифр'
		) && isValid
	isValid =
		validateField(
			'clEmail',
			v => REGEX.EMAIL.test(v),
			'err-email',
			'Некорректный Email'
		) && isValid
	isValid =
		validateField(
			'dob',
			REGEX.NOT_EMPTY,
			'err-dob',
			'Выберите дату'
		) && isValid
	isValid = validateField(
			'ph',
			v => REGEX.PHONE.test(v),
			'err-ph',
			'Некорректный номер телефона'
		) && isValid
	isValid =
		validateField(
			'pi',
			v => REGEX.PI.test(v),
			'err-pi',
			'Заполните поле (мин. 5 символов)'
		) && isValid
	isValid =
		validateField(
			'addr',
			v => REGEX.ADDRESS.test(v),
			'err-addr',
			'Введите адрес проживания'
		) && isValid
	// const phVal = (document.getElementById('ph') as HTMLInputElement).value
	// if (phVal) {
		// isValid =	
	// }

	if (!isValid) return

	const data = {
		email: (document.getElementById('clEmail') as HTMLInputElement).value,
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
		alert('Клиент успешно зарегистрирован!')
		window.router('clients')
	}
}

function validateField(
	id: string,
	rule: (val: string) => boolean,
	errorId: string,
	errorText: string
): boolean {
	const input = document.getElementById(id) as HTMLInputElement
	const errorBox = document.getElementById(errorId) as HTMLElement

	if (!input || !errorBox) return false

	const isValid = rule(input.value.trim())

	if (!isValid) {
		input.classList.add('input-error')
		errorBox.innerText = errorText
		return false
	} else {
		input.classList.remove('input-error')
		errorBox.innerText = ''
		return true
	}
}

const REGEX = {
	EMAIL: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
	PASSPORT_SERIES: /^\d{4}$/,
	PASSPORT_NUMBER: /^\d{6}$/,
	PHONE: /^[+]?[\d\s()-]{10,}$/,
	PI: /^.{5,}$/, 
	ADDRESS: /^.{5,}$/,
	MIN_2: (val: string) => val.length >= 2,
	MIN_4: (val: string) => val.length >= 4,
	MIN_6: (val: string) => val.length >= 6,
	NOT_EMPTY: (val: string) => val.length > 0,
}


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
            <h3 style="margin-bottom: 25px;">Выдача кредита</h3>
            
            <div style="display: flex; flex-direction: column; gap: 20px;"> <!-- Увеличили gap до 20px -->
                
                <div class="form-group">
                    <label style="margin-bottom: 8px; display: block; font-weight: 500;">Продукт</label>
                    <select id="loanProduct" onchange="window.previewSchedule()" style="padding: 12px;">${options}</select>
                    <div id="productLimits" style="margin-top: 12px; font-size: 0.9rem; color: #555; background: #f8f9fa; padding: 15px; border-radius: 8px; border-left: 4px solid var(--accent-rose); line-height: 1.6;">
                    </div>
                </div>
                
                <div class="form-group">
                    <label style="margin-bottom: 8px; display: block; font-weight: 500;">Сумма (₽)</label>
                    <input type="number" id="loanAmount" value="100000" oninput="window.previewSchedule()" style="padding: 12px;">
                    <small id="amountError" style="color: #e74c3c; font-size: 0.85rem; margin-top: 5px; display: block;"></small>
                </div>
                
                <div class="form-group">
                    <label style="margin-bottom: 8px; display: block; font-weight: 500;">Срок (мес)</label>
                    <input type="number" id="loanTerm" value="12" oninput="window.previewSchedule()" style="padding: 12px;">
                    <small id="termError" style="color: #e74c3c; font-size: 0.85rem; margin-top: 5px; display: block;"></small>
                </div>
                
                <div id="previewBox" style="background:#fff0f3; border: 1px solid var(--primary-pink); padding: 20px; border-radius: 12px; line-height: 1.8;">
                    Расчет...
                </div>
                
                <div style="margin-top: 15px; display: flex; gap: 15px;">
                    <button class="btn btn-primary" onclick="window.issueLoan()" style="padding: 12px 24px; font-size: 1rem;">Оформить</button>
                    <button class="btn btn-secondary" onclick="window.router('clients')" style="padding: 12px 24px; font-size: 1rem;">Отмена</button>
                </div>

            </div>
        </div>`

	window.previewSchedule()
}

window.previewSchedule = () => {
	const prodId = Number(
		(document.getElementById('loanProduct') as HTMLInputElement).value
	)
	const amountInput = document.getElementById('loanAmount') as HTMLInputElement
	const termInput = document.getElementById('loanTerm') as HTMLInputElement

	const amount = Number(amountInput.value) || 0
	const term = Number(termInput.value) || 0

	const prod = loadedProducts.find(p => p.id === prodId)
	const previewBox = document.getElementById('previewBox')
	const limitsBox = document.getElementById('productLimits')

	const amountErr = document.getElementById('amountError')
	const termErr = document.getElementById('termError')

	if (prod && previewBox && limitsBox) {
		limitsBox.innerHTML = `
            <!-- Добавили margin-bottom: 8px -->
            <div style="margin-bottom: 8px;">
                <i class="fas fa-coins"></i> 
                Сумма: <b>${formatMoney(prod.minAmount)}</b> — <b>${formatMoney(
			prod.maxAmount
		)} ₽</b>
            </div>
            
            <div>
                <i class="fas fa-calendar-alt"></i> 
                Срок: &nbsp;&nbsp;<b>${prod.minTerm}</b> — <b>${
			prod.maxTerm
		} мес.</b>
            </div>
        `

		let isValid = true

		if (amount < prod.minAmount || amount > prod.maxAmount) {
			amountInput.style.borderColor = '#e74c3c'
			amountErr!.innerText = `Выход за лимиты (от ${prod.minAmount.toLocaleString()} до ${prod.maxAmount.toLocaleString()})`
			isValid = false
		} else {
			amountInput.style.borderColor = '#eee'
			amountErr!.innerText = ''
		}

		if (term < prod.minTerm || term > prod.maxTerm) {
			termInput.style.borderColor = '#e74c3c'
			termErr!.innerText = `Срок от ${prod.minTerm} до ${prod.maxTerm} мес.`
			isValid = false
		} else {
			termInput.style.borderColor = '#eee'
			termErr!.innerText = ''
		}

		if (!isValid) {
			previewBox.innerHTML =
				'<span style="color:#e74c3c"><i class="fas fa-exclamation-triangle"></i> Параметры не соответствуют условиям продукта</span>'
			return
		}

		const res = api.calculatePreview(amount, prod.rate, term)

		previewBox.innerHTML = `
            <div style="display:flex; justify-content:space-between; margin-bottom:5px;">
                <span>Ежемесячный платеж:</span>
                <b style="color: var(--accent-rose); font-size: 1.1em;">
                    ${formatMoney(res.monthlyPayment)} ₽
                </b>
            </div>
            <div style="display:flex; justify-content:space-between;">
                <span>Переплата за весь срок:</span>
                <b>
                    ${formatMoney(res.totalInterest)} ₽
                </b>
            </div>
            <div style="margin-top:5px; font-size:0.85em; color:#666; text-align:right;">
                Ставка: ${prod.rate}%
            </div>
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

	const response = await api.issueLoan(data)

	if (response && response.contractId) {
		const printNow = confirm(
			'Кредит успешно оформлен! Распечатать договор и график платежей?'
		)

		if (printNow) {
			await generateContractPDF(response.contractId)
		}

		window.router('loans')
	}
}

window.showSchedule = async (id: number) => {
	const [schedule, operations] = await Promise.all([
		api.getSchedule(id),
		api.getLoanOperations(id),
	])

	const isClient = currentUser && currentUser.role === 'client'
	let isLoanActive = false
	let currentBalance = 0

	const list = isClient ? await api.getMyLoans() : await api.getLoans()
	const loan = list.find((l: any) => Number(l.id) === Number(id))

	if (loan) {
		currentBalance = loan.balance
		isLoanActive = loan.status === 'active' && loan.balance > 0
	}

	let nextPaymentFound = false
	const scheduleRows = schedule
		.map((r: any) => {
			let actionCell = ''
			if (r.isPaid) {
				actionCell = `<span class="status-badge" style="background:#e8f5e9; color:#2e7d32">Оплачено</span>`
			} else {
				if (isClient && isLoanActive) {
					if (!nextPaymentFound) {
						actionCell = `<button class="btn btn-primary" style="padding: 4px 10px; font-size: 0.8rem;" onclick="window.payInstallment(${r.id}, ${r.paymentAmount}, ${id})">Оплатить</button>`
						nextPaymentFound = true
					} else {
						actionCell = `<span style="color:#999; font-size:0.85rem;"><i class="fas fa-lock"></i> Оплатите предыдущий</span>`
					}
				} else {
					actionCell = `<span class="status-badge" style="background:#ffebee; color:#c62828">Не оплачено</span>`
				}
			}
			return `
            <tr>
                <td>${new Date(r.paymentDate).toLocaleDateString()}</td>
                <td><b>${formatMoney(r.paymentAmount)} ₽</b></td>
                <td style="color:#666">${formatMoney(r.principal)}</td>
                <td style="color:#666">${formatMoney(r.interest)}</td>
                <td>${formatMoney(r.remainingBalance)}</td>
                <td>${actionCell}</td>
            </tr>`
		})
		.join('')

	const operationsRows = operations
		.map((op: any) => {
			let typeName = op.type
			let icon = '<i class="fas fa-circle" style="font-size:8px"></i>'

			if (op.type === 'issue') {
				typeName = 'Выдача кредита'
				icon = '<i class="fas fa-hand-holding-usd" style="color:green"></i>'
			}
			if (op.type === 'scheduled_payment') {
				typeName = 'Платеж'
				icon =
					'<i class="fas fa-check-circle" style="color:var(--accent-rose)"></i>'
			}
			if (op.type === 'early_repayment') {
				typeName = 'Досрочное погашение'
				icon = '<i class="fas fa-star" style="color:gold"></i>'
			}

			return `
            <tr>
                <td style="width: 150px; color: #666;">${new Date(
									op.date
								).toLocaleString()}</td>
                <td style="width: 50px; text-align:center">${icon}</td>
                <td>
                    <div style="font-weight: 500">${typeName}</div>
                    <div style="font-size: 0.85rem; color: #888;">${
											op.desc
										}</div>
                </td>
                <td style="text-align: right; font-weight: bold;">${formatMoney(
									op.amount
								)} ₽</td>
            </tr>
        `
		})
		.join('')

	const backRoute = isClient ? 'my-loans' : 'loans'
	const earlyRepayBtn =
		isClient && isLoanActive
			? `<button class="btn" style="background:var(--accent-rose); color:white; margin-right:10px; border:none;" onclick="window.doEarlyRepayment(${id}, ${currentBalance})"><i class="fas fa-money-check-alt"></i> Полное погашение</button>`
			: ''

	document.getElementById('page-content')!.innerHTML = `
        <div class="card">
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <h3>График платежей</h3>
                <div>
                    ${earlyRepayBtn}
                    ${
											!isClient
												? `<button class="btn btn-primary" onclick="generateContractPDF(${id})"><i class="fas fa-print"></i> Печать</button>`
												: ''
										}
                    <button class="btn btn-secondary" onclick="window.router('${backRoute}')">Назад</button>
                </div>
            </div>
            ${
							isClient && isLoanActive
								? `<div style="margin: 10px 0; font-size: 0.9rem; color: #666;">Текущий долг: <b>${formatMoney(
										currentBalance
								  )} ₽</b></div>`
								: ''
						}
            <br>
            <table>
                <thead><tr><th>Дата</th><th>Сумма</th><th>Осн. долг</th><th>Проценты</th><th>Остаток</th><th>Статус</th></tr></thead>
                <tbody>${scheduleRows}</tbody>
            </table>
        </div>

        <!-- БЛОК ИСТОРИИ ОПЕРАЦИЙ -->
        <div class="card" style="margin-top: 20px;">
            <h3>История операций</h3>
            <table style="margin-top: 15px;">
                <tbody>
                    ${
											operationsRows.length
												? operationsRows
												: '<tr><td colspan="4" style="text-align:center; padding: 20px; color: #999">История пуста</td></tr>'
										}
                </tbody>
            </table>
        </div>
    `
}

function renderLogsPage(logs: any[]) {
	const rows = logs
		.map(l => {
			// Форматируем детали
			let detailsStr = ''
			if (l.details) {
				detailsStr = Object.entries(l.details)
					.map(
						([k, v]) =>
							`<span style="background:#eee; padding:2px 4px; border-radius:4px; font-size:0.8em; margin-right: 4px;">${k}: ${v}</span>`
					)
					.join('')
			}

			let badgeColor = '#f0f0f0'
			if (l.action === 'TOOK_LOAN') badgeColor = '#d8b6efff'
			if (l.action === 'BACKUP_DB') badgeColor = '#e7ccf8ff'
			if (l.action === 'REGISTER_EMPLOYEE') badgeColor = '#f8c7c7ae'
			if (l.action === 'PAYMENT') badgeColor = '#e5f6d4ff' 
			if (l.action === 'EARLY_REPAYMENT') badgeColor = '#fff3e0' 
			if (l.action === 'CREATE_CLIENT') badgeColor = '#f3e5f5' 

			return `
            <tr>
                <td style="font-size:0.85em; color:#666;">${new Date(
									l.date
								).toLocaleString()}</td>
                <td><b>${l.user}</b></td>
                <td><span style="background:${badgeColor}; padding: 4px 8px; border-radius:12px; font-size:0.85em; font-weight:500">${
				l.action
			}</span></td>
                <td>${l.entity} #${l.entityId}</td>
                <td>${detailsStr}</td>
            </tr>
        `
		})
		.join('')

	return `
        <div class="card">
            <h3>Журнал действий (Аудит)</h3>
            
            <!-- ИЗМЕНЕНИЕ: padding: 20px, gap: 30px -->
            <div style="background: #fafafa; padding: 20px; border-radius: 8px; margin-bottom: 20px; display: flex; gap: 30px; align-items: flex-end;">
                
                <div class="form-group" onchange="window.applyLogFilters()" style="margin-bottom:0; flex:1">
                    <label style="margin-bottom: 8px; display:block;">Тип события</label>
                    <select id="filterAction" style="width: 100%;">
                        <option value="">Все события</option>
                        <option value="TOOK_LOAN">Выдача кредита</option>
                        <option value="EARLY_REPAYMENT">Досрочное погашение</option>
                        <option value="PAYMENT">Платеж по графику</option>
                        <option value="CREATE_CLIENT">Создание клиента</option>
                        <option value="REGISTER_EMPLOYEE">Регистрация сотрудника</option>
						<option value="BACKUP_DB">Создание резервной копии</option>
                    </select>
                </div>
                
                <div class="form-group" oninput="window.applyLogFilters()" style="margin-bottom:0; flex:1">
                    <label style="margin-bottom: 8px; display:block;">Дата (с какого числа)</label>
                    <input type="date" id="filterDate" style="width: 100%;">
                </div>
            </div>

            <table>
                <!-- ... заголовок таблицы ... -->
                <thead>
                    <tr>
                        <th>Время</th>
                        <th>Кто выполнил</th>
                        <th>Действие</th>
                        <th>Объект</th>
                        <th>Детали</th>
                    </tr>
                </thead>
                <tbody id="logsTableBody">
                    ${
											rows.length > 0
												? rows
												: '<tr><td colspan="5" style="text-align:center; padding:20px; color:#888">Записей не найдено</td></tr>'
										}
                </tbody>
            </table>
        </div>
    `
}

window.applyLogFilters = async () => {
	const action = (document.getElementById('filterAction') as HTMLInputElement)
		.value
	const date = (document.getElementById('filterDate') as HTMLInputElement).value

	currentLogFilters = {}
	if (action) currentLogFilters.action = action
	if (date) currentLogFilters.from = date

	await updateLogsTableOnly()
}

function getPageTitle(t: string) {
	const m: any = {
		dashboard: 'Обзор',
		clients: 'Управление клиентами',
		loans: 'Список кредитов',
		employees: 'Сотрудники',
	}
	return m[t] || ''
}

async function generateContractPDF(contractId: number) {
	const contract = await api.getLoanById(contractId)
	if (!contract) return

	const schedule = await api.getSchedule(contractId)

	const today = new Date().toLocaleDateString('ru-RU')

	const tableBody = [
		[
			{ text: '№', style: 'tableHeader' },
			{ text: 'Дата', style: 'tableHeader' },
			{ text: 'Платеж', style: 'tableHeader' },
			{ text: 'Осн. долг', style: 'tableHeader' },
			{ text: 'Проценты', style: 'tableHeader' },
			{ text: 'Остаток', style: 'tableHeader' },
		],
	]

	schedule.forEach((row: any, index: number) => {
		tableBody.push([
			(index + 1).toString(),
			new Date(row.paymentDate).toLocaleDateString(),
			row.paymentAmount.toFixed(2),
			row.principal.toFixed(2),
			row.interest.toFixed(2),
			row.remainingBalance.toFixed(2),
		])
	})

	const docDefinition = {
		info: {
			title: `Договор №${contract.contractNumber}`,
			author: 'RoseBank AIS',
		},
		content: [
			{ text: 'ПАО «ROSEBANK»', style: 'brand', alignment: 'right' },
			{
				text: `КРЕДИТНЫЙ ДОГОВОР № ${contract.contractNumber}`,
				style: 'header',
				margin: [0, 20, 0, 10],
			},

			{
				columns: [
					{ text: 'г. Москва', width: '*' },
					{ text: today, width: 'auto' },
				],
				margin: [0, 0, 0, 20],
			},

			{ text: '1. ПРЕДМЕТ ДОГОВОРА', style: 'subheader' },
			{
				text: [
					'Банк обязуется предоставить Заемщику (',
					{ text: contract.clientName, bold: true },
					') денежные средства (Кредит) в размере ',
					{ text: `${contract.amount.toLocaleString()} руб.`, bold: true },
					' на срок ',
					{ text: `${contract.termMonths} мес.`, bold: true },
					' под ',
					{ text: `${contract.interestRate}%`, bold: true },
					' годовых.',
				],
				margin: [0, 5, 0, 10],
				alignment: 'justify',
			},
			{
				text: `Кредитный продукт: ${contract.productName}`,
				margin: [0, 0, 0, 20],
			},

			{ text: '2. ГРАФИК ПЛАТЕЖЕЙ', style: 'subheader' },
			{
				style: 'tableExample',
				table: {
					headerRows: 1,
					widths: ['auto', '*', 'auto', 'auto', 'auto', 'auto'],
					body: tableBody,
				},
				layout: 'lightHorizontalLines',
			},

			{
				text: '3. АДРЕСА И РЕКВИЗИТЫ СТОРОН',
				style: 'subheader',
				margin: [0, 30, 0, 10],
			},
			{
				columns: [
					{
						width: '*',
						text: [
							{ text: 'БАНК:\n', bold: true },
							'ПАО «RoseBank»\n',
							'Адрес: г. Москва, ул. Пушкина, дом Колотушкина 1\n',
							'БИК: 044525000\n\n',
							'Менеджер: ___________________',
						],
					},
					{
						width: '*',
						text: [
							{ text: 'ЗАЕМЩИК:\n', bold: true },
							`${contract.clientName}\n`,
							'Паспорт: РФ\n\n\n',
							'Подпись: ___________________',
						],
					},
				],
			},
		],
		styles: {
			brand: { fontSize: 10, color: '#C06C84', bold: true },
			header: { fontSize: 16, bold: true, alignment: 'center' },
			subheader: { fontSize: 12, bold: true, margin: [0, 10, 0, 5] },
			tableHeader: { bold: true, fontSize: 10, color: 'black' },
			tableExample: { margin: [0, 5, 0, 15], fontSize: 9 },
		},
	}

	pdfMake.createPdf(docDefinition).open()
}

window.doBackup = async () => {
	if (!confirm('Создать полную резервную копию базы данных?')) return

	const res = await api.createBackup()
	if (res && res.message) {
		alert(`Успешно! Файл: ${res.file}`)
	}
}

window.payInstallment = async (
	scheduleId: number,
	amount: number,
	contractId: number
) => {
	if (!confirm(`Выполнить списание средств в размере ${amount.toFixed(2)} ₽?`))
		return

	const res = await api.makePayment(scheduleId)

	if (res && res.message) {
		alert('Платеж успешно выполнен!')
		window.showSchedule(contractId)
	}
}

function formatMoney(amount: number): string {
	return amount.toLocaleString('ru-RU', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2,
		useGrouping: true,
	})
}

window.doEarlyRepayment = async (contractId: number, balance: number) => {
	if (
		!confirm(
			`Вы действительно хотите выполнить ПОЛНОЕ досрочное погашение?\n\nСумма списания: ${formatMoney(
				balance
			)} ₽\n\nКредит будет закрыт, будущие проценты аннулированы.`
		)
	) {
		return
	}

	const res = await api.repayEarly(contractId)

	if (res && res.message) {
		alert(`Успешно! Списано: ${formatMoney(res.paidAmount)} ₽. Кредит закрыт.`)
		window.router('my-loans')
	}
}

function renderStatsPage(stats: any, financeReport: any[]) {
    
    const reportRows = financeReport.map(r => {
        const color = r.net >= 0 ? '#2e7d32' : '#c62828';
        const sign = r.net > 0 ? '+' : '';

        return `
            <tr>
                <td><b>${r.month}</b></td>
                <td>${formatMoney(r.issued)} ₽</td>
                <td>${formatMoney(r.repaid)} ₽</td>
                <td style="color: ${color}; font-weight: bold;">
                    ${sign}${formatMoney(r.net)} ₽
                </td>
            </tr>
        `;
    }).join('');

    return `
        <!-- Блок 1: Карточки -->
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px;">
            <div class="card" style="background: linear-gradient(135deg, #fff0f3 0%, #fff 100%); border-left: 5px solid var(--accent-rose);">
                <h4 style="color: #666; margin-bottom: 10px;">Всего выдано (тело кредитов)</h4>
                <div style="font-size: 1.8em; font-weight: bold; color: var(--accent-rose);">
                    ${formatMoney(stats.totalIssued / 100)} ₽
                </div>
            </div>
            
            <div class="card" style="background: linear-gradient(135deg, #e8f5e9 0%, #fff 100%); border-left: 5px solid #2e7d32;">
                <h4 style="color: #666; margin-bottom: 10px;">Всего возвращено (платежи)</h4>
                <div style="font-size: 1.8em; font-weight: bold; color: #2e7d32;">
                    ${formatMoney(stats.totalRepaid / 100)} ₽
                </div>
            </div>
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
            
            <!-- Блок 2: Диаграмма -->
            <div class="card">
                <h3>Портфель продуктов</h3>
                <div style="height: 300px; display: flex; justify-content: center;">
                    <canvas id="productsChart"></canvas>
                </div>
            </div>

            <!-- Блок 3: Финансовая таблица (НОВОЕ) -->
            <div class="card">
                <h3>Финансовый поток (Cash Flow)</h3>
                <div style="max-height: 300px; overflow-y: auto;">
                    <table>
                        <thead>
                            <tr>
                                <th>Месяц</th>
                                <th>Выдача</th>
                                <th>Возврат</th>
                                <th>Итог</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${reportRows.length ? reportRows : '<tr><td colspan="4" style="text-align:center; padding:20px; color:#999">Нет данных</td></tr>'}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

async function updateLogsTableOnly() {
    const tbody = document.querySelector('#logsTableBody');
    if (!tbody) return; 

    const logs = await api.getLogs(currentLogFilters);

    const rowsHtml = logs.map((l: any) => {
        let detailsStr = '';
        if (l.details) {
            detailsStr = Object.entries(l.details)
                .map(([k, v]) => `<span style="background:#eee; padding:2px 4px; border-radius:4px; font-size:0.8em; margin-right: 4px;">${k}: ${v}</span>`)
                .join('');
        }

        let badgeColor = '#f0f0f0';
        if (l.action === 'TOOK_LOAN') badgeColor = '#d8b6efff'
		if (l.action === 'BACKUP_DB') badgeColor = '#e7ccf8ff'
		if (l.action === 'REGISTER_EMPLOYEE') badgeColor = '#f8c7c7ae'
		if (l.action === 'PAYMENT') badgeColor = '#e5f6d4ff'
		if (l.action === 'EARLY_REPAYMENT') badgeColor = '#fff3e0'
		if (l.action === 'CREATE_CLIENT') badgeColor = '#f3e5f5' 

        return `
            <tr>
                <td style="font-size:0.85em; color:#666;">${new Date(l.date).toLocaleString()}</td>
                <td><b>${l.user}</b></td>
                <td><span style="background:${badgeColor}; padding: 4px 8px; border-radius:12px; font-size:0.85em; font-weight:500">${l.action}</span></td>
                <td>${l.entity} #${l.entityId}</td>
                <td>${detailsStr}</td>
            </tr>
        `;
    }).join('');

    tbody.innerHTML = rowsHtml.length > 0 ? rowsHtml : '<tr><td colspan="5" style="text-align:center; padding:30px; color:#888">Записей не найдено</td></tr>';
}

function initStatsChart(data: any[]) {
    const ctx = document.getElementById('productsChart') as HTMLCanvasElement;
    if (!ctx) return;

    const labels = data.map(d => d.label);
    const values = data.map(d => d.value);
    
    const colors = [
        '#C06C84', '#6C5B7B', '#355C7D', '#F67280', '#F8B195', '#A8E6CF'
    ];

    new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: labels,
            datasets: [{
                label: 'Количество кредитов',
                data: values,
                backgroundColor: colors,
                hoverOffset: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            }
        }
    });
}

function initApp() {
	const savedToken = localStorage.getItem('authToken')
	const savedUser = localStorage.getItem('userData')

	if (savedToken && savedUser) {
		try {
			currentUser = JSON.parse(savedUser)
			window.router('dashboard')
		} catch (e) {
			window.logout()
		}
	} else {
		renderLogin()
	}
}

renderLogin()
initApp()