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
    availableForms: [], // Список доступных форм
    lectureFormId: null,
    examFormId: null
  },
  methods: {
    // Простой хэш пароля (для примера; в реальности используйте bcrypt на бэкенде!)
    hashPassword(password) {
      // В реальном проекте НИКОГДА не используйте такой способ!
      // Это только для демонстрации.
      let hash = 0;
      for (let i = 0; i < password.length; i++) {
        const char = password.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Преобразование в 32‑битное целое
      }
      return hash.toString();
    },

    async login() {
      try {
        const { data, error } = await supabase
          .from('users')
          .select('*')
          .eq('username', this.username)
          .single();

        if (error || !data) {
          alert('Неверный логин или пароль');
          return;
        }

        const passwordHash = this.hashPassword(this.password);
        if (data.password_hash !== passwordHash) {
          alert('Неверный пароль');
          return;
        }

        this.user = data;
        await this.loadFormIds();
      } catch (err) {
        console.error('Ошибка при входе:', err);
        alert('Произошла ошибка при входе');
      }
    },

    async register() {
      try {
        const passwordHash = this.hashPassword(this.regPassword);

        const { data, error } = await supabase
          .from('users')
          .insert([{
            username: this.regUsername,
            password_hash: passwordHash,
            role: 'user' // По умолчанию — простой пользователь
          }]);

        if (error) {
          console.error('Ошибка регистрации:', error);
          alert('Ошибка регистрации. Возможно, такой логин уже занят.');
          return;
        }

        alert('Регистрация успешна! Теперь войдите в систему.');
        this.showRegister = false;
        this.regUsername = '';
        this.regPassword = '';
      } catch (err) {
        console.error('Ошибка при регистрации:', err);
        alert('Произошла ошибка при регистрации');
      }
    },

    logout() {
      this.user = null;
      this.activeTab = 'home';
    },

    async loadFormIds() {
      try {
        // Загружаем ID форм для запросов на лекцию и экзамен
        const { data: lectureForm, error: lectureError } = await supabase
          .from('forms')
          .select('id')
          .eq('title', 'Запрос на Лекцию')
          .eq('is_active', true)
          .single();

        if (!lectureError && lectureForm) {
          this.lectureFormId = lectureForm.id;
        }

        const { data: examForm, error: examError } = await supabase
          .from('forms')
          .select('id')
          .eq('title', 'Запрос на Экзамен')
          .eq('is_active', true)
          .single();

        if (!examError && examForm) {
          this.examFormId = examForm.id;
        }
      } catch (err) {
        console.error('Ошибка загрузки ID форм:', err);
      }
    }
  },
  async mounted() {
    // При загрузке страницы проверяем, есть ли активный сеанс
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data: user, error } = await supabase
        .from('users')
        .select('*')
        .eq('id', session.user.id)
        .single();
      if (!error) {
        this.user = user;
        await this.loadFormIds();
      }
    }
  }
});
