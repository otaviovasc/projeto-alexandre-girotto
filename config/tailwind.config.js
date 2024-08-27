/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*',
  ],
  theme: {
    extend: {
      backgroundImage: {
        'bg-fundo': "url('/app/assets/images/fundo.png')",
      },
      fontFamily: {
        alice: ['Alice', 'serif'],
        dm: ['DM Sans', 'sans-serif'],
      },
      colors: {
        "verde-escuro": "#2f4538",
        "preto-fill": "#3c3c3c",
        "terracota": "#877c7a",
        "laranja": "#ffbd59",
        "creme": "#f6f4eb",
      },
      padding: {
        22: "5.5rem",
        24: "6rem",
        28: "7rem",
        30: "7.5rem",
        32: "8rem",
        36: "9rem",
        40: "10rem",
      },
      margin: {
        22: "5.5rem",
        24: "6rem",
        28: "7rem",
        30: "7.5rem",
        32: "8rem",
        36: "9rem",
        40: "10rem",
      },
      maxWidth: {
        "1/2": "50%",
        "6/10": "60%",
        "8/10": "80%",
        "9/10": "95%",
      },
      backgroundImage: theme => ({
                'fundo': "url('<%= asset_path('fundo.png') %>')"
            }),
    },
  },
  plugins: [],
}
