// Инициализация Supabase
const supabaseUrl = 'https://innljjhvmyzgfqhenmjq.supabase.co';
const supabaseKey = 'sb_publishable_ViVCLNkbxhKos0sVCWlcOA_eZQEDDO3';
const supabase = supabase.createClient(supabaseUrl, supabaseKey);

// Главное Vue‑приложение
const app = new Vue({
    el: '#app',
    data: {
        user: null, // Текущий авторизованный пользователь
        username: '',
        password: '',
        showRegister: false,
        regUsername: '',
        regPassword: '',
        activeTab: 'home',
        lectureFormId: null,
        examFormId: null
    },
    methods: {
        async login() {
            const { data, error } = await supabase
                .from('users')
                .select('*')
                .eq('username', this.username)
                .single();

            if (error || !data) {
                alert('Неверный логин или пароль');
                return;
            }

            // Простой хэш (в реальности используйте bcrypt на бэкенде!)
            const passwordHash = this.hashPassword(this.password);
            if (data.password_hash !== passwordHash) {
                alert('Неверный пароль');
                return;
            }

            this.user = data;
            this.loadFormIds();
        },

        async register() {
            const passwordHash = this.hashPassword(this.regPassword);

            const { data, error } = await supabase
                .from('users')
                .insert([{
                    username: this.regUsername,
                    password_hash: passwordHash,
                    role: 'user' // По умолчанию — простой пользователь
                }]);

            if (
