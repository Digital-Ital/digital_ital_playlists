/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/views/**/*.erb',
    './app/helpers/**/*.rb',
    './app/assets/javascripts/**/*.js',
    './app/javascript/**/*.js',
    './app/views/**/*.html'
  ],
  safelist: [
    // Family gradients (static + hover variants) used from DB-configured strings
    'from-green-600/80', 'to-yellow-600/80',
    'hover:from-green-500/90', 'hover:to-yellow-500/90',

    'from-red-600/80', 'to-orange-600/80',
    'hover:from-red-500/90', 'hover:to-orange-500/90',

    'from-purple-600/80', 'to-pink-600/80',
    'hover:from-purple-500/90', 'hover:to-pink-500/90',

    // Weed Songs variants (green -> purple families)
    'from-emerald-600/80', 'to-purple-600/80',
    'hover:from-emerald-500/90', 'hover:to-purple-500/90',

    'from-lime-600/80', 'to-violet-600/80',
    'hover:from-lime-500/90', 'hover:to-violet-500/90',

    'from-green-700/80', 'to-fuchsia-600/80',
    'hover:from-green-600/90', 'hover:to-fuchsia-500/90',

    // Generic grays used as fallbacks
    'from-gray-700/80', 'to-gray-600/80',
    'hover:from-gray-600/90', 'hover:to-gray-500/90'
  ]
}


