/**
 * Direct Cache Warmer - Simple approach for testing
 * This script directly calls the main API to cache books from CSV
 */

const MAIN_API_URL = 'https://books.ooheynerds.com';
const RATE_LIMIT = 1500; // 1.5 seconds between calls

// Sample books from 2023.csv for testing
const SAMPLE_BOOKS = [
  { title: 'Yellowface', author: 'R.F. Kuang' },
  { title: 'Demon Copperhead', author: 'Barbara Kingsolver' },
  { title: 'Trust', author: 'Hernan Diaz' },
  { title: 'Blackouts', author: 'Justin Torres' },
  { title: 'Prophet Song', author: 'Paul Lynch' },
  { title: 'The Bee Sting', author: 'Paul Murray' },
  { title: 'Western Lane', author: 'Chetna Maroo' },
  { title: 'This Other Eden', author: 'Paul Harding' },
  { title: 'Study for Obedience', author: 'Sarah Bernstein' },
  { title: 'The Heaven & Earth Grocery Store', author: 'James McBride' }
];

async function warmCacheDirectly() {
  console.log(`🚀 Starting direct cache warming for ${SAMPLE_BOOKS.length} books...`);
  
  let successCount = 0;
  let errorCount = 0;
  
  for (let i = 0; i < SAMPLE_BOOKS.length; i++) {
    const book = SAMPLE_BOOKS[i];
    const progress = `${i + 1}/${SAMPLE_BOOKS.length}`;
    
    console.log(`📖 [${progress}] Searching: "${book.title}" by ${book.author}`);
    
    try {
      // Search by title - this will populate the cache
      const titleSearchUrl = `${MAIN_API_URL}/search/title?q=${encodeURIComponent(book.title)}&limit=5&sort=relevance&includeAuthorData=true`;
      
      const response = await fetch(titleSearchUrl, {
        method: 'GET',
        headers: {
          'User-Agent': 'Direct-Cache-Warmer/1.0',
          'Accept': 'application/json'
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        const foundBooks = data.items?.length || 0;
        console.log(`   ✅ Found ${foundBooks} results - cached successfully`);
        successCount++;
        
        // If we found results, also warm author cache
        if (foundBooks > 0) {
          await new Promise(resolve => setTimeout(resolve, 500));
          
          const authorSearchUrl = `${MAIN_API_URL}/search/author?q=${encodeURIComponent(book.author)}&limit=5`;
          const authorResponse = await fetch(authorSearchUrl);
          
          if (authorResponse.ok) {
            const authorData = await authorResponse.json();
            console.log(`   📚 Author cache warmed: ${authorData.items?.length || 0} author results`);
          }
        }
      } else {
        console.log(`   ⚠️  API error: ${response.status} ${response.statusText}`);
        errorCount++;
      }
      
    } catch (error) {
      console.log(`   ❌ Error: ${error.message}`);
      errorCount++;
    }
    
    // Rate limiting
    if (i < SAMPLE_BOOKS.length - 1) {
      console.log(`   ⏳ Waiting ${RATE_LIMIT/1000}s...`);
      await new Promise(resolve => setTimeout(resolve, RATE_LIMIT));
    }
  }
  
  console.log(`\n🎉 Cache warming complete!`);
  console.log(`✅ Successful: ${successCount}`);
  console.log(`❌ Errors: ${errorCount}`);
  console.log(`📊 Success rate: ${Math.round((successCount / SAMPLE_BOOKS.length) * 100)}%`);
}

// Execute if running directly
if (typeof module !== 'undefined' && require.main === module) {
  warmCacheDirectly().catch(console.error);
}

module.exports = { warmCacheDirectly, SAMPLE_BOOKS };